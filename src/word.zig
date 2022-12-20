// gluumy's canonical implementation and standard library is released to the
// public domain (or your jurisdiction's closest legal equivalent) under the
// Creative Commons Zero 1.0 dedication, distributed alongside this source in a
// file called COPYING.

const Object = @import("./object.zig").Object;
const Runtime = @import("./runtime.zig").Runtime;

// TODO: This should almost certainly not be anyerror.
// TODO: handle stack juggling
pub const PrimitiveWord = fn (*Runtime) anyerror!void;
pub const WordImplementation = union(enum) {
    // I can see a world where this should return something other than void
    // to allow for optimizations later... probably an enum/bitfield of
    // what, if any, changes were made to the stack or its objects?
    //
    // Note that by the function signature alone we can infer that, while
    // gluumy pretends to be an immutable-by-default language at the glass,
    // it's still a Good Old Fashioned Mutable Ball Of Bit Spaghetti under
    // the hood for performance reasons.
    Primitive: *const PrimitiveWord,
    Compound: []Word,
    HeapLit: *Object,
};

// TODO: Docs.
pub const Word = struct {
    // Those finding they need more tag space should compile their own
    // project-specific gluumy build changing the constant as appropriate.
    // Unlike many languages where mucking about with the internals is
    // faux-pas, in gluumy it is encouraged on a "if you know you really need
    // it" basis.
    //
    // TODO: configurable in build.zig
    pub const MAX_GLOBAL_TAGS = 256;
    pub const TAG_ARRAY_SIZE = MAX_GLOBAL_TAGS / 8;

    flags: packed struct {
        hidden: bool,
    },

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
    tags: [TAG_ARRAY_SIZE]u8,

    impl: WordImplementation,
};
