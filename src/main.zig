// gluumy: a hackable, type-safe, minimalist, stack-based programming language
//
// (it's pronounced "gloomy" (or maybe "glue me"), and is spelled in lowercase,
// always)
//
//  _.    _  |         ._ _       ._  o  _  |_ _|_   |_   _   _  o ._   _
// (_|   (_| | |_| |_| | | | \/   | | | (_| | | |_   |_) (/_ (_| | | | _>
//        _|                 /           _|                   _|
//
//
// Hi, welcome to the party, my name is klardotsh and I'll be your tour guide
// this evening. Before we begin, let's take a quick moment to make sure your
// editor is in a sane state for reading this:
//
// 1) it needs to be wide enough to see the trailing > at the end of the next line:
// <------------------------------------------------------------------------------------->
//
// look yes I know that's 90 characters but *it's 2022 for zeus's sake*
//
// 2) it needs to be able to handle UTF-8! again, *it's 20-freakin-22*, we
//    standardized this stuff years ago
//
//
// Cool, now let's also make sure your host system, assuming you actually want
// to build this thing (and I hope you do, and I hope you play with it and
// build awesome things with it!), is in order. At time of writing, gluumy
// builds against Zig 0.9, and *only* Zig 0.9. If this code is
// forwards-compatible, great, hopefully I get around to updating this blurb
// some time. Assume this code is not, and will never be, backwards-compatible
// to Zig 0.8 or any previous versions. Aside from the Zig standard library,
// the basic gluumy REPL has no system-level dependencies (though I'm aware
// that, at time of writing, Zig itself requires a full Clang+LLVM stack, and
// thus bootstrapping gluumy on non-standard architectures may be painful).
//
//
// With that said, let's begin the "host" side of gluumy.

const std = @import("std");
const Allocator = std.mem.Allocator;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// Words in gluumy work somewhat like words in Forth, but with some critically
// important details largely stemming from gluumy's type system, and its
// relatively higher-level nature than Forths that target bare-metal assembly
// (though there's theoretically nothing stopping someone from implementing an
// ASM code generator for gluumy...). Without assuming knowledge of Forth,
// however: a word is a series of UTF-8 characters (excluding 0x20 (space),
// 0x09 (tab), and 0x0A (newline)) identifying an entry in the words
// dictionary, which itself contains a series of instructions, not terribly
// unlike a function definition in most languages.
//
// TODO: more commentary

// First, let's set up some constants. WORD_BUF_LEN is how big of a buffer
// we're willing to allocate to store words as they're input (be that by
// keyboard or by source file: we'll see how that works later). We have to draw
// a line _somewhere_, and since 1KB of RAM is beyond feasible to allocate on
// most systems I'd foresee writing gluumy for, that's the max word length
// until I'm convinced otherwise. This should be safe to change and the
// implementation will scale proportionally.
const WORD_BUF_LEN = 1024;

const STACK_LENGTH = 4096;
const TOP_TYPE_ID: TypeSignature.IdType = 0;

// TODO: determine if this is temporary, or will actually exist in the final
// implementation. it would probably make words like dup more sane, but then,
// type hints like ( @1 -> @1 ) to make "generics" could get us just as good of
// an effect (I think)
var TopType = TypeSignature.init(false, TOP_TYPE_ID);

const Dictionary = struct {
    const Self = @This();
    const Store = std.StringHashMap(WordImplementationsByTypeSignature);

    allocator: *Allocator,
    store: *Store,

    fn init(allocator: *Allocator) !Self {
        var store = try allocator.create(Store);
        store.* = Store.init(allocator.*);

        return Self{
            .allocator = allocator,
            .store = store,
        };
    }

    // TODO take type signature into account
    fn lookup(self: Self, name: []const u8) ?*Word {
        std.debug.print("looking up \"{s}\"\n", .{name});
        return self.store.get(name).?.getPtr(&TopType);
    }

    // TODO take type signature into account
    fn register(self: Self, name: []u8, word: Word) !void {
        var name_storage = try self.allocator.alloc(u8, name.len);
        std.mem.copy(u8, name_storage, name);

        var entry = try self.store.getOrPut(name_storage);

        if (!entry.found_existing) {
            var impls = try self.allocator.create(WordImplementationsByTypeSignature);
            impls.* = WordImplementationsByTypeSignature.init(self.allocator.*);
            entry.value_ptr = impls;
        }

        _ = try entry.value_ptr.getOrPutValue(&TopType, word);

        std.debug.print("stored word \"{s}\" of type {any} with {any}\n", .{
            name_storage,
            TopType,
            word,
        });
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

const WordImplementationsByTypeSignature = std.AutoHashMap(*TypeSignature, Word);

const TypeSignature = packed struct {
    const Self = @This();

    const IdType = u20;
    const PrimaryPaddingSize = u11;

    reserved_padding: PrimaryPaddingSize,
    is_container: bool,
    id: IdType,

    fn init(is_container: bool, id: IdType) Self {
        return Self{
            .reserved_padding = 0,
            .is_container = is_container,
            .id = id,
        };
    }

    test {
        try std.testing.expectEqual(32, @bitSizeOf(@This()));
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

const Word = struct {
    const Self = @This();

    flags: packed struct {
        immediate: bool,
        hidden: bool,
    },
    implementation: WordImplementation,

    fn initSimplePrimitive(impl: *const WordImplementation.PrimitiveImplementation) Self {
        return Self{
            .flags = .{
                .immediate = false,
                .hidden = false,
            },
            .implementation = WordImplementation{ .Primitive = impl },
        };
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

const WordImplementation = union(enum) {
    const PrimitiveImplementation = (fn (Runtime, *Stack) Runtime.Error!*Stack);

    Primitive: *const PrimitiveImplementation,
    WordSequence: []*Word,
    Constant: *Object,

    comptime {
        std.testing.refAllDecls(@This());
    }
};

const Object = union(enum) {
    const Self = @This();

    // change to suit taste/target platform
    const StandardFloatType = f64;

    // TODO: figure out how this should work, it's going to be pretty critical
    // for getting the language off the ground (read: I don't feel like
    // reimplementing, say, LibreSSL in gluumy)
    Foreign: *anyopaque,

    UnsignedInt: usize,
    SignedInt: isize,
    Float: StandardFloatType,

    fn is_number(self: Self) bool {
        return switch (self) {
            .UnsignedInt, .SignedInt, .Float => true,
            else => false,
        };
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

// TODO: is it possible to not park the pointer to the stack_node within the
// stack_node.data itself? seems super ugly, but is the only way I could think
// of to avoid allocating a whole other store for "in use" StackNodePool
// entities
//
// besides, anything that's a pointer to anyopaque seems... overly hacky
const ObjectWrapper = struct {
    entity: ?*anyopaque,
    obj: Object,
};

const Stack = std.atomic.Stack(?ObjectWrapper);
const StackNodePool = std.atomic.Stack(*Stack.Node);

const InterpState = enum(u8) {
    INTERPRET = 0,
    COMPILE = 1,
    IMMEDIATE = 2,
};

const Runtime = struct {
    const Self = @This();

    const Error = error{
        StackUnderflow,
        RuntimeTypeError,
    };

    allocator: *Allocator,
    stack: Stack,
    stack_node_pool: *StackNodePool,
    word_dictionary: Dictionary,
    state: InterpState,
    type_id_counter: TypeSignature.IdType,

    fn init(allocator: *Allocator) !Self {
        var stack_node_pool = try allocator.create(StackNodePool);
        stack_node_pool.* = StackNodePool.init();

        var stack_nodes = try allocator.alloc(StackNodePool.Node, STACK_LENGTH);

        var runtime = Self{
            .allocator = allocator,
            .stack = Stack.init(),
            .stack_node_pool = stack_node_pool,

            .word_dictionary = try Dictionary.init(allocator),

            .state = InterpState.INTERPRET,
            .type_id_counter = TOP_TYPE_ID + 1,
        };

        for (stack_nodes[0..]) |*node_slot| {
            var node = try runtime.allocator.create(Stack.Node);
            node.* = Stack.Node{
                .next = null,
                .data = null,
            };

            node_slot.* = StackNodePool.Node{
                .next = null,
                .data = node,
            };
            runtime.stack_node_pool.push(node_slot);
        }

        return runtime;
    }

    fn populate_primitve_words(self: *Self) !void {
        // TODO optimization:
        // self.word_dictionary.store.ensureTotalCapacity(X);
        //
        // where X is the number of primitives we're registering, perhaps store
        // in an anonymous slice

        var star_word = "*".*;
        try self.word_dictionary.register(
            star_word[0..],
            Word.initSimplePrimitive(&prim_word_mul),
        );
    }

    fn prim_word_mul(self: Self, stack: *Stack) Error!*Stack {
        const right = stack.pop().?.data;
        const left = stack.pop().?.data;

        if (right == null or left == null) {
            return Error.StackUnderflow;
        }

        // TODO return old nodes to pool
        //
        // TODO clean up old Objects, they currently just "leak" by way of
        // using the ArenaAllocator (read: use the GPA instead)
        try switch (right.?.obj) {
            Object.Float => |rval| switch (left.?.obj) {
                Object.Float => |lval| {
                    const result = rval * lval;
                    var stack_node = self.stack_node_pool.pop().?;
                    stack_node.data.data.?.obj = Object{ .Float = result };
                    stack_node.data.data.?.entity = stack_node;
                    stack.push(stack_node.data);
                },
                else => Error.RuntimeTypeError,
            },
            Object.UnsignedInt => |rval| switch (left.?.obj) {
                Object.UnsignedInt => |lval| {
                    const result = rval * lval;
                    var stack_node = self.stack_node_pool.pop().?;
                    stack_node.data.data.?.obj = Object{ .UnsignedInt = result };
                    stack_node.data.data.?.entity = stack_node;
                    stack.push(stack_node.data);
                },
                else => Error.RuntimeTypeError,
            },
            Object.SignedInt => |rval| switch (left.?.obj) {
                Object.SignedInt => |lval| {
                    const result = rval * lval;
                    var stack_node = self.stack_node_pool.pop().?;
                    stack_node.data.data.?.obj = Object{ .SignedInt = result };
                    stack_node.data.data.?.entity = stack_node;
                    stack.push(stack_node.data);
                },
                else => Error.RuntimeTypeError,
            },
            else => Error.RuntimeTypeError,
        };

        return stack;
    }

    fn feed_word_TEMP(self: Self, word: []const u8) !void {
        // TODO integrate type system, everything is currently assumed
        // TOP_TYPE_ID since, well, duh, there's no type system yet
        const found_word = self.word_dictionary.lookup(word).?;

        // TODO implement
        if (found_word.flags.immediate) unreachable;
        if (found_word.flags.hidden) unreachable;
    }

    comptime {
        std.testing.refAllDecls(Self);
    }
};

pub fn main() anyerror!u8 {
    var gpa_allocator = gpa.allocator();
    var arena_alloc = std.heap.ArenaAllocator.init(gpa_allocator);
    var arena_allocator = arena_alloc.allocator();

    // TODO: fix this
    var runtime = try Runtime.init(&arena_allocator);

    try runtime.populate_primitve_words();

    const raw_stdin = std.io.getStdIn();
    //var stdin = std.io.bufferedReader(raw_stdin.reader());
    //var stdin_reader = stdin.reader();
    var stdin_reader = raw_stdin.reader();
    const raw_stdout = std.io.getStdOut();
    var stdout = std.io.bufferedWriter(raw_stdout.writer());
    var stdout_writer = stdout.writer();

    var word_buf: [WORD_BUF_LEN]u8 = undefined;
    var word_len: usize = 0;

    // park this var to appease compiler
    _ = stdout_writer;

    while (true) {
        const word_byte = stdin_reader.readByte() catch |err| switch (err) {
            error.EndOfStream => {
                if (word_len > 0) {
                    try runtime.feed_word_TEMP(word_buf[0..word_len]);
                }

                break;
            },
            else => |e| return e,
        };

        word_buf[word_len] = word_byte;
        word_len += 1;

        switch (word_byte) {
            ' ', '\t', '\n' => {
                try runtime.feed_word_TEMP(word_buf[0 .. word_len - 1]);
                word_len = 0;
                continue;
            },
            else => continue,
        }
    }

    try stdout.flush();

    return 0;
}

comptime {
    std.testing.refAllDecls(@This());
}
