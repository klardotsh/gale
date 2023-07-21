// Copyright (C) 2023 Josh Klar aka "klardotsh" <josh@klar.sh>
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
// REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
// FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
// INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
// LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
// OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
// PERFORMANCE OF THIS SOFTWARE.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testAllocator: Allocator = std.testing.allocator;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

const builtin = @import("builtin");

const _object = @import("./object.zig");
const _stack = @import("./stack.zig");
const _word = @import("./word.zig");

const helpers = @import("./helpers.zig");
const well_known_entities = @import("./well_known_entities.zig");

const CompoundImplementation = _word.CompoundImplementation;
const HeapLitImplementation = _word.HeapLitImplementation;
const InternalError = @import("./internal_error.zig").InternalError;
const Object = _object.Object;
const ParsedWord = @import("./parsed_word.zig").ParsedWord;
const PrimitiveImplementation = _word.PrimitiveImplementation;
const Shape = @import("./shape.zig").Shape;
const Stack = _stack.Stack;
const StackManipulationError = _stack.StackManipulationError;
const Types = @import("./types.zig");
const Word = _word.Word;
const WordList = @import("./word_list.zig").WordList;
const WordMap = @import("./word_map.zig").WordMap;
const WordSignature = @import("./word_signature.zig").WordSignature;
const WellKnownShape = well_known_entities.WellKnownShape;
const WellKnownShapeStorage = well_known_entities.WellKnownShapeStorage;
const WellKnownSignature = well_known_entities.WellKnownSignature;
const WellKnownSignatureStorage = well_known_entities.WellKnownSignatureStorage;

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
    const WORD_SPLITTING_CHARS: [3]u8 = .{
        helpers.CHAR_NEWLINE,
        helpers.CHAR_SPACE,
        helpers.CHAR_TAB,
    };

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

    // TODO: configurable in build.zig
    const SIGNATURE_POOL_DEFAULT_SIZE = 8192;

    /// All symbols are interned by their raw "string" contents and stored
    /// behind a typical garbage collection structure (Rc([]u8)) for later
    /// pulling onto a stack.
    const SymbolPool = std.StringHashMap(Types.HeapedSymbol);

    // TODO: use HashSet if https://github.com/ziglang/zig/issues/6919 ever
    // moves
    const WordSignaturePool = std.hash_map.HashMap(
        WordSignature,
        void,
        struct {
            pub const eql = std.hash_map.getAutoEqlFn(WordSignature, @This());
            pub fn hash(ctx: @This(), key: WordSignature) u64 {
                _ = ctx;
                if (comptime std.meta.trait.hasUniqueRepresentation(WordSignature)) {
                    return std.hash.Wyhash.hash(0, std.mem.asBytes(&key));
                } else {
                    var hasher = std.hash.Wyhash.init(0);
                    std.hash.autoHashStrat(&hasher, key, .DeepRecursive);
                    return hasher.final();
                }
            }
        },
        std.hash_map.default_max_load_percentage,
    );

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
    signatures: WordSignaturePool,
    well_known_shapes: WellKnownShapeStorage,
    well_known_signatures: WellKnownSignatureStorage,

    pub fn init(alloc: Allocator) !Self {
        var dictionary = WordMap.init(alloc);
        try dictionary.ensureTotalCapacity(DICTIONARY_DEFAULT_SIZE);

        var symbol_pool = SymbolPool.init(alloc);
        try symbol_pool.ensureTotalCapacity(SYMBOL_POOL_DEFAULT_SIZE);

        var signature_pool = WordSignaturePool.init(alloc);
        try signature_pool.ensureTotalCapacity(SIGNATURE_POOL_DEFAULT_SIZE);

        var rt = Self{
            .alloc = alloc,
            .dictionary = dictionary,
            .private_space = PrivateSpace.init(),
            .stack = try Stack.init(alloc, null),
            .symbols = symbol_pool,
            .signatures = signature_pool,
            .well_known_shapes = well_known_entities.shape_storage(),
            .well_known_signatures = well_known_entities.signature_storage(),
        };

        try well_known_entities.populate(&rt);

        return rt;
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

        self.signatures.clearAndFree();
        self.signatures.deinit();
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

    /// Run a string of input in this Runtime, splitting into words along the
    /// way. Any number of WORD_SPLITTING_CHARS are used as delimiters to split
    /// the input into potentially-parseable words, which are then passed to
    /// `dispatch_word_by_input`.
    pub fn eval(self: *Self, input: []const u8) !void {
        var current_word: []const u8 = undefined;
        var start_idx: usize = 0;
        var in_word = false;
        var in_string = false;

        chars: for (input) |chr, idx| {
            if (in_string and chr != helpers.CHAR_QUOTE_DBL) continue;

            if (chr == helpers.CHAR_QUOTE_DBL) {
                if (in_word and !in_string) {
                    return InternalError.InvalidWordName;
                }

                in_string = !in_string;
            }

            // TODO: benchmark whether this should be explicitly unrolled or
            // just left to the compiler to figure out
            inline for (WORD_SPLITTING_CHARS) |candidate| {
                if (chr == candidate) {
                    if (!in_word) continue :chars;

                    current_word = input[start_idx..idx];
                    try self.dispatch_word_by_input(current_word);
                    in_word = false;
                    continue :chars;
                }
            }

            if (!in_word) {
                start_idx = idx;
                in_word = true;
            }

            if (idx == input.len - 1) {
                current_word = input[start_idx..];
                try self.dispatch_word_by_input(current_word);
            }
        }
    }

    /// Pass a single pre-whitespace-trimmed word to ParsedWord.from_input and
    /// either place the literal onto the stack or lookup and run the word (if
    /// it exists), as appropriate.
    pub fn dispatch_word_by_input(self: *Self, input: []const u8) !void {
        switch (try ParsedWord.from_input(input)) {
            .Simple, .Ref => return InternalError.Unimplemented,
            .String => |str| {
                const interned_str = try self.get_or_put_string(str);
                try self.stack_push_string(interned_str.value_ptr);
            },
            .Symbol => |sym| {
                const interned_sym = try self.get_or_put_symbol(sym);
                try self.stack_push_symbol(interned_sym.value_ptr);
            },
            .NumFloat => |num| try self.stack_push_float(num),
            .SignedInt => |num| try self.stack_push_sint(num),
            .UnsignedInt => |num| try self.stack_push_uint(num),
        }
    }

    pub fn run_word(self: *Self, word: *Types.HeapedWord) !void {
        // TODO: Stack compatibility check against the WordSignature.

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

    pub fn get_or_put_string(self: *Self, str: []const u8) !GetOrPutResult(Types.HeapedString) {
        // TODO: intern this similarly to symbols
        const stored = try self.alloc.alloc(u8, str.len);
        std.mem.copy(u8, stored[0..], str);
        const heaped = try self.alloc.create(Types.HeapedString);
        heaped.* = Types.HeapedString.init(stored);
        return .{
            .value_ptr = heaped,
            .found_existing = false,
        };
    }

    /// Retrieve the previously-interned Symbol's Rc
    pub fn get_or_put_symbol(self: *Self, sym: []const u8) !GetOrPutResult(Types.HeapedSymbol) {
        var entry = try self.symbols.getOrPut(sym);
        if (!entry.found_existing) {
            const stored = try self.alloc.alloc(u8, sym.len);
            std.mem.copy(u8, stored[0..], sym);
            entry.value_ptr.* = Types.HeapedSymbol.init(stored);
            // TODO: uncomment this to fix known memory bugs found when
            // implementing test_protolang 19 Jan 2023
            // try entry.value_ptr.increment();
        }
        return .{
            .value_ptr = entry.value_ptr,
            .found_existing = entry.found_existing,
        };
    }

    /// Take a WordSignature by value and, if it is new to this Runtime, store
    /// it. Return a GetOrPutResult which will contain a pointer to the stored
    /// WordSignature. Each unique signature will be stored a maximum of one
    /// time in this Runtime.
    ///
    /// Can fail by way of allocation errors only.
    pub fn get_or_put_word_signature(self: *Self, sig: WordSignature) !GetOrPutResult(WordSignature) {
        var entry = try self.signatures.getOrPut(sig);
        return .{
            .value_ptr = entry.key_ptr,
            .found_existing = entry.found_existing,
        };
    }

    pub fn get_well_known_shape(self: *Self, req: WellKnownShape) *Shape {
        return &self.well_known_shapes[@enumToInt(req)];
    }

    pub fn get_well_known_word_signature(self: *Self, req: WellKnownSignature) *WordSignature {
        return self.well_known_signatures[@enumToInt(req)];
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
    pub fn word_from_compound_impl(
        self: *Self,
        impl: CompoundImplementation,
        sig: ?Word.SignatureState,
    ) !*Types.HeapedWord {
        return try self.send_word_to_heap(Word.new_compound_untagged(impl, sig));
    }

    /// Heap-wraps a heaplit word definition. How meta.
    pub fn word_from_heaplit_impl(
        self: *Self,
        impl: HeapLitImplementation,
        sig: ?Word.SignatureState,
    ) !*Types.HeapedWord {
        return try self.send_word_to_heap(Word.new_heaplit_untagged(impl, sig));
    }

    /// Heap-wraps a primitive word definition.
    pub fn word_from_primitive_impl(
        self: *Self,
        impl: PrimitiveImplementation,
        sig: ?Word.SignatureState,
    ) !*Types.HeapedWord {
        return try self.send_word_to_heap(Word.new_primitive_untagged(impl, sig));
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

        // TODO WARNING: For now, this always makes invalid words (without a
        // signature). Need to figure out the correct way to plumb signatures
        // here given that the runtime will be using a builder pattern to
        // attach them.
        var heap_for_word = try self.word_from_compound_impl(compound_storage, null);

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

    pub fn stack_push_array(self: *Self, value: *Types.HeapedArray) !void {
        self.stack = try self.stack.do_push_array(value);
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

test "Runtime.eval: integration" {
    var rt = try Runtime.init(testAllocator);
    defer rt.deinit_guard_for_empty_stack();

    // TODO: comments depend on @BEFORE_WORD support, or could become part of
    // ParsedWord if we want to push it down to barer metal.
    //
    // try rt.eval("{{ 1 }}");
    // try expectError(
    //     StackManipulationError.Underflow,
    //     rt.stack_pop(),
    // );

    // Push four numbers to the stack individually
    try rt.eval("1");
    try rt.eval("2/i");
    try rt.eval("3.14");
    try rt.eval("4");

    // Push a symbol for giggles
    try rt.eval(":something");

    // Push a string too
    try rt.eval("\"foo and a bit of bar\"");

    // Now push several more numbers in one library call
    try rt.eval("5/u 6/i 7.5");

    var float_signed_unsigned = try rt.stack_pop_trio();
    defer {
        rt.release_heaped_object_reference(&float_signed_unsigned.near);
        rt.release_heaped_object_reference(&float_signed_unsigned.far);
        rt.release_heaped_object_reference(&float_signed_unsigned.farther);
    }
    try expectApproxEqAbs(
        @as(f64, 7.5),
        float_signed_unsigned.near.Float,
        @as(f64, 0.0000001),
    );
    try expectEqual(@as(isize, 6), float_signed_unsigned.far.SignedInt);
    try expectEqual(@as(usize, 5), float_signed_unsigned.farther.UnsignedInt);

    var foo_str = try rt.stack_pop();
    defer {
        rt.release_heaped_object_reference(&foo_str);
    }
    try expectEqualStrings("foo and a bit of bar", foo_str.String.value.?);

    var something_symbol = try rt.stack_pop();
    defer {
        // TODO: uncomment this once Runtime.get_or_put_symbol is fixed to
        // increment refcount correctly, this *should* be leaking RAM as-is but
        // is not, unearthing a whole class of bugs (5 addresses leaking in 1
        // test in libgale alone)
        //
        // rt.release_heaped_object_reference(&something_symbol);
    }
    try expectEqualStrings("something", something_symbol.Symbol.value.?);

    var inferunsigned_float_signed = try rt.stack_pop_trio();
    defer {
        rt.release_heaped_object_reference(&inferunsigned_float_signed.near);
        rt.release_heaped_object_reference(&inferunsigned_float_signed.far);
        rt.release_heaped_object_reference(&inferunsigned_float_signed.farther);
    }
    try expectEqual(@as(isize, 4), inferunsigned_float_signed.near.SignedInt);
    try expectApproxEqAbs(
        @as(f64, 3.14),
        inferunsigned_float_signed.far.Float,
        @as(f64, 0.0000001),
    );
    try expectEqual(@as(isize, 2), inferunsigned_float_signed.farther.SignedInt);

    var bottom = try rt.stack_pop();
    defer rt.release_heaped_object_reference(&bottom);
    try expectEqual(@as(isize, 1), bottom.SignedInt);
}

test {
    std.testing.refAllDecls(@This());
}
