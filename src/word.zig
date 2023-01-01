// gluumy's canonical implementation and standard library is released to the
// public domain (or your jurisdiction's closest legal equivalent) under the
// Creative Commons Zero 1.0 dedication, distributed alongside this source in a
// file called COPYING.

const std = @import("std");

const Object = @import("./object.zig").Object;
const Runtime = @import("./runtime.zig").Runtime;
const Types = @import("./types.zig");

// TODO: This should almost certainly not be anyerror.
// TODO: handle stack juggling
pub const PrimitiveWord = fn (*Runtime) anyerror!void;

pub const CompoundImplementation = []Types.GluumyWord;
pub const HeapLitImplementation = *Object;
pub const PrimitiveImplementation = *const PrimitiveWord;
pub const WordImplementation = union(enum) {
    // I can see a world where this should return something other than void
    // to allow for optimizations later... probably an enum/bitfield of
    // what, if any, changes were made to the stack or its objects?
    //
    // Note that by the function signature alone we can infer that, while
    // gluumy pretends to be an immutable-by-default language at the glass,
    // it's still a Good Old Fashioned Mutable Ball Of Bit Spaghetti under
    // the hood for performance reasons.
    Primitive: PrimitiveImplementation,
    Compound: CompoundImplementation,
    HeapLit: HeapLitImplementation,
};

pub const Flags = packed struct {
    hidden: bool,
};

// TODO: Docs.
pub const Word = struct {
    const Self = @This();

    // Those finding they need more tag space should compile their own
    // project-specific gluumy build changing the constant as appropriate.
    // Unlike many languages where mucking about with the internals is
    // faux-pas, in gluumy it is encouraged on a "if you know you really need
    // it" basis.
    //
    // TODO: configurable in build.zig
    pub const MAX_GLOBAL_TAGS = 256;
    pub const TAG_ARRAY_SIZE = MAX_GLOBAL_TAGS / 8;

    flags: Flags,

    // This is thinking ahead for functionality I want to be able to provide:
    // while gluumy is in no way a "pure functional" language like Haskell, and
    // while I frankly don't know enough about type systems or their theory to
    // (currently) implement an effects tracking system, it'd still be nice to
    // be able to signal to callers (of the human variety) in their dev
    // environments, "hey, this method calls out to IO!". Tags could then be
    // transitive through a word stack, so a "main" word that calls "getenv"
    // and "println" (or whatever those functions end up called) would get
    // "tainted" with the 'IO tag.
    //
    // The thought behind limiting global tags is that it forces judicial use
    // of these things. Given that Words are the fundamental mechanism for
    // computing, there will be *many* of these things, and so they will become
    // memory-costly if unbounded.
    //
    // These are simple bitmasks, and so with the default of 256 global tags,
    // we'll use 32 bytes per word.
    //
    // TODO: a pointer is only 8 bytes (or 4 on x32), does it make more sense
    // to save 24 bytes of RAM at the cost of a pointer jump whenever we care
    // about accessing these tags? I assume (upfront assumptions in language
    // design, lolololol) we'll only really care about these in the
    // LSP/devtools/debugger/etc. cases, and almost never at runtime. Further,
    // this could allow memory deduplication by storing each tags set exactly
    // once (getOrPut pattern as with hash maps etc.), which is almost
    // certainly a useful property.
    tags: [TAG_ARRAY_SIZE]u8,

    impl: WordImplementation,

    pub fn new_untagged(impl: WordImplementation) Self {
        return Self{
            .flags = .{ .hidden = false },
            .tags = [_]u8{0} ** TAG_ARRAY_SIZE,
            .impl = impl,
        };
    }

    pub fn new_compound_untagged(impl: CompoundImplementation) Self {
        return new_untagged(.{ .Compound = impl });
    }

    pub fn new_heaplit_untagged(impl: HeapLitImplementation) Self {
        return new_untagged(.{ .HeapLit = impl });
    }

    pub fn new_primitive_untagged(impl: PrimitiveImplementation) Self {
        return new_untagged(.{ .Primitive = impl });
    }

    pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        return switch (self.impl) {
            .Primitive => {},
            .HeapLit => |obj| {
                obj.deinit(alloc);
                alloc.destroy(obj);
            },
            .Compound => |compound| {
                var any_alive_remaining = false;
                for (compound) |iword| {
                    if (!iword.decrement_and_prune(.DeinitInnerWithAllocDestroySelf, alloc)) {
                        any_alive_remaining = true;
                    }
                }

                if (!any_alive_remaining) {
                    alloc.free(compound);
                }
            },
        };
    }
};
