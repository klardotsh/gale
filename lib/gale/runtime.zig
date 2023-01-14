// Gale's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testAllocator: Allocator = std.testing.allocator;
const expectEqual = std.testing.expectEqual;

const builtin = @import("builtin");

const _object = @import("./object.zig");
const _word = @import("./word.zig");

const CompoundImplementation = _word.CompoundImplementation;
const HeapLitImplementation = _word.HeapLitImplementation;
const InternalError = @import("./internal_error.zig").InternalError;
const Object = _object.Object;
const PrimitiveImplementation = _word.PrimitiveImplementation;
const Stack = @import("./stack.zig").Stack;
const Types = @import("./types.zig");
const Word = _word.Word;
const WordList = @import("./word_list.zig").WordList;
const WordMap = @import("./word_map.zig").WordMap;

pub const Runtime = struct {
    const Self = @This();

    pub const InterpreterMode = enum(u8) {
        Exec = 0,
        Symbol = 1,
        Ref = 2,
    };

    const PrivateSpace = struct {
        interpreter_mode: InterpreterMode,

        pub fn init() PrivateSpace {
            return PrivateSpace{
                .interpreter_mode = InterpreterMode.Exec,
            };
        }
    };

    /// These characters separate identifiers, and can broadly be defined as
    /// "typical ASCII whitespace": UTF-8 codepoints 0x20 (space), 0x09 (tab),
    /// and 0x0A (newline). This technically leaves the door open to
    /// tricky-to-debug behaviors like using 0xA0 (non-breaking space) as
    /// identifiers. With great power comes great responsibility. Don't be
    /// silly.
    const WORD_SPLITTING_CHARS: [3]u8 = .{ ' ', '\t', '\n' };

    /// Speaking of Words: WORD_BUF_LEN is how big of a buffer we're willing to
    /// allocate to store words as they're input. We have to draw a line
    /// _somewhere_, and since 1KB of RAM is beyond feasible to allocate on
    /// most systems I'd foresee writing gale for, that's the max word length
    /// until I'm convinced otherwise. This should be safe to change and the
    /// implementation will scale proportionally.
    //
    // TODO: configurable in build.zig
    const WORD_BUF_LEN = 1024;

    // TODO: configurable in build.zig
    const DICTIONARY_DEFAULT_SIZE = 4096;

    // TODO: configurable in build.zig
    const SYMBOL_POOL_DEFAULT_SIZE = 4096;
    /// All symbols are interned by their raw "string" contents and stored
    /// behind a typical garbage collection structure (Rc([]u8)) for later
    /// pulling onto a stack.
    const SymbolPool = std.StringHashMap(Types.HeapedSymbol);

    fn GetOrPutResult(comptime T: type) type {
        return struct {
            value_ptr: *T,
            found_existing: bool,
        };
    }

    alloc: Allocator,
    dictionary: WordMap,
    private_space: PrivateSpace,
    stack: *Stack,
    symbols: SymbolPool,

    pub fn init(alloc: Allocator) !Self {
        var dictionary = WordMap.init(alloc);
        try dictionary.ensureTotalCapacity(DICTIONARY_DEFAULT_SIZE);

        var symbol_pool = SymbolPool.init(alloc);
        try symbol_pool.ensureTotalCapacity(SYMBOL_POOL_DEFAULT_SIZE);

        return .{
            .alloc = alloc,
            .dictionary = dictionary,
            .private_space = PrivateSpace.init(),
            .stack = try Stack.init(alloc, null),
            .symbols = symbol_pool,
        };
    }

    pub fn deinit(self: *Self) void {
        // First, nuke everything on the stack using this horribly named method
        // (TODO for the love of god find better names for these things).
        self.stack.deinit_from_bottom();
        self.deinit_shared();
    }

    /// The rest of the deinit() sequence, shared between the standard deinit()
    /// and the test-mode-only deinit_guard_for_empty_stack().
    fn deinit_shared(self: *Self) void {
        // Now, we need to nuke all defined words, which is a bit fidgety since
        // they're referenced by their symbol identifiers which themselves may
        // need to be garbage collected in this process.
        var dictionary_iter = self.dictionary.iterator();
        while (dictionary_iter.next()) |entry| {
            // Drop our reference to the symbol naming this WordList (and free
            // the underlying u8 slice if appropriate).
            _ = entry.key_ptr.*.decrement_and_prune(.FreeInnerDestroySelf, self.alloc);
            // Now defer to WordList.deinit to clean its own self up, making
            // the assumption that it, too, will destroy any orphaned objects
            // along the way.
            entry.value_ptr.deinit(self.alloc);
        }
        // And now these two lines should remove all remaining metadata the
        // HashMap itself stores and leave us with a defunct HashMap.
        self.dictionary.clearAndFree();
        self.dictionary.deinit();

        var symbol_iter = self.symbols.valueIterator();
        while (symbol_iter.next()) |entry| {
            _ = entry.decrement_and_prune(.FreeInner, self.alloc);
        }
        self.symbols.clearAndFree();
        self.symbols.deinit();
    }

    /// Deinitialize this Runtime, panicking if anything was left on the stack.
    /// This can only be used in tests, and will @compileError in non-test
    /// builds. This is often the correct function to use in tests, as it
    /// forces manual stack cleanup of expected entities, and any garbage left
    /// on the stack at that point (bugs) will panic the test.
    ///
    ///
    /// This should be called with `defer` immediately after the Runtime is
    /// instantiated (thus the use of `@panic` instead of assertions from
    /// `std.testing`, since `defer try` is not valid in Zig).
    pub fn deinit_guard_for_empty_stack(self: *Self) void {
        // This is also handled in Stack.deinit_guard_for_empty, but the error
        // will be more clear originating from the actual function the caller
        // used rather than down-stack, since both functions have the same
        // usecases.
        if (!builtin.is_test) {
            @compileError("deinit_guard_for_empty_stack should NEVER be used outside of the test framework");
        }

        // first, ensure the stack is empty and if so, deinitialize it.
        self.stack.deinit_guard_for_empty();
        self.deinit_shared();
    }

    /// Release a reference to an Object sent to the heap with
    /// `stack_pop_to_heap`, freeing the underlying memory per the rules of
    /// `Object.deinit` if no longer used.
    pub fn release_heaped_object_reference(self: *Self, ptr: *Object) void {
        ptr.deinit(self.alloc);
    }

    /// Retrieve the previously-interned Symbol's Rc
    pub fn get_or_put_symbol(self: *Self, sym: []const u8) !GetOrPutResult(Types.HeapedSymbol) {
        var entry = try self.symbols.getOrPut(sym);
        if (!entry.found_existing) {
            const stored = try self.alloc.alloc(u8, sym.len);
            std.mem.copy(u8, stored[0..], sym);
            entry.value_ptr.* = Types.HeapedSymbol.init(stored);
        }
        return .{
            .value_ptr = entry.value_ptr,
            .found_existing = entry.found_existing,
        };
    }

    /// Takes a bare Word struct, wraps it in a refcounter, and returns a
    /// pointer to the resultant memory. Does not wrap it in an Object for
    /// direct placement on a Stack.
    fn send_word_to_heap(self: *Self, bare: Word) !*Types.HeapedWord {
        const heap_space = try self.alloc.create(Types.HeapedWord);
        heap_space.* = Types.HeapedWord.init(bare);
        return heap_space;
    }

    /// Heap-wraps a compound word definition.
    pub fn word_from_compound_impl(self: *Self, impl: CompoundImplementation) !*Types.HeapedWord {
        return try self.send_word_to_heap(Word.new_compound_untagged(impl));
    }

    /// Heap-wraps a heaplit word definition. How meta.
    pub fn word_from_heaplit_impl(self: *Self, impl: HeapLitImplementation) !*Types.HeapedWord {
        return try self.send_word_to_heap(Word.new_heaplit_untagged(impl));
    }

    /// Heap-wraps a primitive word definition.
    pub fn word_from_primitive_impl(self: *Self, impl: PrimitiveImplementation) !*Types.HeapedWord {
        return try self.send_word_to_heap(Word.new_primitive_untagged(impl));
    }

    // Right now, Zig doesn't have a way to narrow `targets` type from anytype,
    // which is super disappointing, but being brainstormed on:
    // https://github.com/ziglang/zig/issues/5404
    pub fn define_word_va(self: *Self, identifier: *Types.HeapedSymbol, targets: anytype) !void {
        try identifier.increment();
        var dict_entry = try self.dictionary.getOrPut(identifier);
        if (!dict_entry.found_existing) {
            dict_entry.value_ptr.* = WordList.init(self.alloc);
        }

        const compound_storage = try self.alloc.alloc(*Types.HeapedWord, targets.len);
        inline for (targets) |target, idx| compound_storage[idx] = target;

        var heap_for_word = try self.word_from_compound_impl(compound_storage);
        // TODO should this increment actually be stashed away in a dictionary
        // helper method somewhere? should there be a
        // Runtime.unstacked_word_from_compound_impl that handles the increment
        // for us (using Rc.init_referenced) since we can't rely on
        // Stack.do_push's implicit increment?
        try heap_for_word.increment();

        try dict_entry.value_ptr.append(heap_for_word);
    }

    pub fn priv_space_set_byte(self: *Self, member: u8, value: u8) InternalError!void {
        return switch (member) {
            0 => self.private_space.interpreter_mode = @intToEnum(InterpreterMode, value),
            else => InternalError.ValueError,
        };
    }

    test "priv_space_set_byte" {
        var rt = try Self.init(testAllocator);
        defer rt.deinit();
        try expectEqual(@as(u8, 0), @enumToInt(rt.private_space.interpreter_mode));
        try rt.priv_space_set_byte(0, 1);
        try expectEqual(@as(u8, 1), @enumToInt(rt.private_space.interpreter_mode));
    }

    pub fn run_word(self: *Self, word: *Types.HeapedWord) !void {
        if (word.value) |iword| {
            switch (iword.impl) {
                .Compound => return InternalError.Unimplemented, // TODO
                .HeapLit => |lit| self.stack = try self.stack.do_push(lit.*),
                .Primitive => |impl| try impl(self),
            }
        } else {
            // TODO: determine if there's a better/more concise error to pass
            // here, perhaps by somehow triggering this and seeing what states
            // can even leave us here
            return InternalError.EmptyWord;
        }
    }

    pub fn stack_peek(self: *Self) !*Object {
        return self.stack.do_peek();
    }

    pub fn stack_peek_pair(self: *Self) !Types.PeekPair {
        return self.stack.do_peek_pair();
    }

    pub fn stack_peek_trio(self: *Self) !Types.PeekTrio {
        return self.stack.do_peek_trio();
    }

    /// Remove the top item from the stack and return it. If there are no
    /// contents remaining, a StackManipulationError.Underflow is raised.
    pub fn stack_pop(self: *Self) !Object {
        const popped = try self.stack.do_pop();
        self.stack = popped.now_top_stack;
        return popped.item;
    }

    /// Remove the top item from the stack, move it to the heap, and return the
    /// new address to the data. Use `release_heaped_object_reference` to later
    /// drop a reference to this data (and, if applicable, collect the
    /// garbage). If there are no contents remaining, a
    /// StackManipulationError.Underflow is raised.
    pub fn stack_pop_to_heap(self: *Self) !*Object {
        const popped = try self.stack.do_pop();
        const banish_target = try self.alloc.create(Object);
        errdefer self.alloc.destroy(banish_target);
        banish_target.* = popped.item;
        self.stack = popped.now_top_stack;
        return banish_target;
    }

    /// Remove the top two items from the stack and return them. If there
    /// aren't at least two Objects remaining, a
    /// StackManipulationError.Underflow is raised. If this happens with one
    /// Object on the Stack, it will remain there.
    pub fn stack_pop_pair(self: *Self) !Types.PopPairExternal {
        const popped = try self.stack.do_pop_pair();
        self.stack = popped.now_top_stack;
        return Types.PopPairExternal{
            .near = popped.near,
            .far = popped.far,
        };
    }

    /// Remove the top three items from the stack and return them. If there
    /// aren't at least three Objects remaining, a
    /// StackManipulationError.Underflow is raised. If this happens with one or
    /// two Objects on the Stack, they will remain there.
    pub fn stack_pop_trio(self: *Self) !Types.PopTrioExternal {
        const popped = try self.stack.do_pop_trio();
        self.stack = popped.now_top_stack;
        return Types.PopTrioExternal{
            .near = popped.near,
            .far = popped.far,
            .farther = popped.farther,
        };
    }

    pub fn stack_push_bool(self: *Self, value: bool) !void {
        self.stack = try self.stack.do_push_bool(value);
    }

    pub fn stack_push_float(self: *Self, value: f64) !void {
        self.stack = try self.stack.do_push_float(value);
    }

    pub fn stack_push_sint(self: *Self, value: isize) !void {
        self.stack = try self.stack.do_push_sint(value);
    }

    /// Push a HeapedString to the stack by reference. As this string is
    /// expected to already be heap-allocated and reference-counted, it is also
    /// expected that callers have already handled any desired interning before
    /// reaching this point.
    pub fn stack_push_string(self: *Self, value: *Types.HeapedString) !void {
        self.stack = try self.stack.do_push_string(value);
    }

    /// Push a HeapedSymbol to the stack by reference. As this symbol is
    /// expected to already be heap-allocated and reference-counted, it is also
    /// expected that callers have already handled any desired interning before
    /// reaching this point.
    pub fn stack_push_symbol(self: *Self, value: *Types.HeapedSymbol) !void {
        self.stack = try self.stack.do_push_symbol(value);
    }

    pub fn stack_push_uint(self: *Self, value: usize) !void {
        self.stack = try self.stack.do_push_uint(value);
    }

    pub fn stack_push_raw_word(self: *Self, value: *Types.HeapedWord) !void {
        self.stack = try self.stack.do_push_word(value);
    }

    pub const StackWranglingOperation = enum {
        DropTopObject,

        DuplicateTopObject,
        DuplicateTopTwoObjectsShuffled,

        SwapTopTwoObjects,
    };

    // TODO: return type?
    pub fn stack_wrangle(self: *Self, operation: StackWranglingOperation) !void {
        switch (operation) {
            .DropTopObject => self.stack = try self.stack.do_drop(),

            .DuplicateTopObject => self.stack = try self.stack.do_dup(),
            .DuplicateTopTwoObjectsShuffled => self.stack = try self.stack.do_2dupshuf(),

            .SwapTopTwoObjects => try self.stack.do_swap(),
        }
    }
};

test {
    std.testing.refAllDecls(@This());
}
