// Gale's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testAllocator: Allocator = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

const InternalError = @import("./internal_error.zig").InternalError;
const Types = @import("./types.zig");
const WordSignature = @import("./word_signature.zig");

// TODO: Configurable in build.zig
const NUM_INLINED_SHAPES_IN_GENERICS: usize = 2;

// TODO: Should this ever be localized or configurable in build.zig?
const ANONYMOUS_SHAPE_FILLER_NAME = "<anonymous shape>";

// TODO: move to a common file somewhere
const AtomicUsize = std.atomic.Atomic(usize);

pub const Shape = struct {
    const Self = @This();

    given_name: ?*Types.HeapedSymbol = null,
    member_words: ?[]MemberWord = null,
    contents: ShapeContents,

    /// Shape Evolution is how we implement the "newtype" concept: say I have
    /// a method which can only take a FibonnaciNumber. All fibonnaci numbers
    /// can be represented within the space of unsigned integers, but not all
    /// unsigned integers are valid fibonnaci numbers. In many languages, the
    /// type-safe way to represent this is to wrap ("box") the integer in some
    /// sort of class/dictionary/struct, perhaps with a property name of .value
    /// or (in Rust's case) something like .0. In Gale, like Haskell and other
    /// languages, we can instead create a shape that is *exactly* and *only*
    /// an unsigned integer under the hood, and is disparate from all other
    /// unsigned integers (or other types composed from them: perhaps Meters).
    /// We call this concept "evolving" a shape, to disambiguate it from
    /// various other concepts that I might otherwise borrow the names of
    /// for this purpose (say, "aliasing", which is *also* something you can
    /// do to a shape, but this has nothing to do with our "newtype" concept).
    ///
    /// The evolved shape will retain `member_words` (making this a reasonably
    /// lightweight way to non-destructively extend or override an existing
    /// Shape's contract requirements), and all "Self Words" defined on the
    /// root will be "inherited" to this evolved shape (with Self redefined).
    /// Take care with evolving bounded shapes, because `in-bounds?` will be
    /// inherited unless explicitly overridden.
    ///
    /// Yes, dear reader, this is, other than a memory simplicity trick,
    /// an approximation of prototypical inheritance, and generally a path
    /// towards loose object orientation.
    evolved_from: ?*Self = null,
    evolution_id: usize = 0,
    evolutions_spawned: AtomicUsize = AtomicUsize.init(0),

    /// Evolve this Shape into an independent Shape laid out identically in
    /// memory which will not fulfill Word Signatures expecting the root
    /// Shape (and vice-versa). This is analogous to the "newtype" paradigm
    /// in other languages; see Shape.evolved_from docstring for more details
    /// and particulars about what the evolved Shape will look like or be able
    /// to do.
    ///
    /// The evolved shape will not have a `given_name`, but will have a pointer
    /// to the parent in `evolved_from` which may have a `given_name` from which
    /// to derive a new `given_name`, if desired.
    pub fn evolve(self: *Self) Self {
        const evolution_id = self.evolutions_spawned.fetchAdd(1, .Monotonic);

        return Self{
            .given_name = null,
            .member_words = self.member_words,
            .contents = self.contents,
            .evolved_from = self,
            .evolution_id = evolution_id,
            .evolutions_spawned = AtomicUsize.init(0),
        };
    }

    /// Returns the given name of the shape or :anonymous if no name is known.
    /// Accepts an allocator which is used to create the space for the
    /// :anonymous symbol if needed. As usual for any type implemented with
    /// Rc(_), the return value of this method must be decremented and
    /// eventually pruned to avoid memory leaks.
    ///
    /// This method can fail in any ways an allocation can fail, and further,
    /// will panic if the underlying Rc of a symbol it attempts to increment
    /// refcounts of is corrupt.
    //
    // TODO: This shouldn't take an allocator directly, but should take a
    // symbol pool from which we can request an existing :anonymous if it
    // already exists (perhaps we should ensure that it always will). The
    // current implementation wastes tons of RAM in the event of calling name()
    // many times on unnamed shapes. This basically entails decoupling a
    // conceptual SymbolPool from the Runtime where it currently exists,
    // because I blatantly refuse to initialize an entire Runtime{} here
    // just to use its symbol pool... at least for as long as I can get away
    // with it.
    pub fn name(self: *Self, alloc: Allocator) !*Types.HeapedSymbol {
        var given_name_symbol: *Types.HeapedSymbol = undefined;

        if (self.given_name) |gname| {
            given_name_symbol = gname;
        } else {
            const symbol_space = try alloc.alloc(u8, ANONYMOUS_SHAPE_FILLER_NAME.len);
            std.mem.copy(u8, symbol_space, ANONYMOUS_SHAPE_FILLER_NAME);
            given_name_symbol = try alloc.create(Types.HeapedSymbol);
            // TODO: determine if we consider this to be a "gale-side reference"
            // as per the docs of Rc.init_referenced. If not, it may make sense
            // to update the docstring there, because we'll have made it a lie...
            given_name_symbol.* = Types.HeapedSymbol.init(symbol_space);
        }

        if (given_name_symbol.increment()) |_| {
            return given_name_symbol;
        } else |err| {
            switch (err) {
                InternalError.AttemptedResurrectionOfExhaustedRc => @panic("shape name's symbol's underlying Rc has been exhausted, this is a memory management bug in Gale"),
                else => @panic("failed to increment shape name's underlying Rc"),
            }
        }
    }

    test "anonymous shapes have a filler name" {
        var shape = Self{ .contents = .Empty };
        const shape_name = try shape.name(testAllocator);
        defer {
            _ = shape_name.decrement_and_prune(.FreeInnerDestroySelf, testAllocator);
        }
        try expectEqualStrings(ANONYMOUS_SHAPE_FILLER_NAME, shape_name.value.?);
    }

    test "requesting the name of a shape qualifies as owning a ref to the underlying symbol" {
        const given_name = "AnotherEternity";
        const symbol_space = try testAllocator.alloc(u8, given_name.len);
        std.mem.copy(u8, symbol_space, given_name);
        const name_symbol = try testAllocator.create(Types.HeapedSymbol);
        name_symbol.* = Types.HeapedSymbol.init_referenced(symbol_space);
        defer {
            _ = name_symbol.decrement_and_prune(.FreeInnerDestroySelf, testAllocator);
        }

        var shape = Self{ .contents = .Empty };
        shape.given_name = name_symbol;

        const shape_name = try shape.name(testAllocator);
        defer {
            _ = shape_name.decrement_and_prune(.FreeInnerDestroySelf, testAllocator);
        }
        try expectEqual(shape_name.strong_count.value, 2);
    }

    // TODO: return context of *why* the shapes are incompatible
    /// Determine, if possible statically, whether two shapes are compatible,
    /// using `self` as the reference (in other words: "is `other` able to
    /// fulfill my constraints?"). Null values are indeterminate statically
    /// and generally speaking need to fall back to runtime determination via
    /// BoundsCheckable (using in-bounds?).
    pub fn compatible_with(self: *Self, other: *Self) ?bool {
        return switch (self.contents) {
            .Empty => other.contents == .Empty and self.evolved_from == other.evolved_from and self.evolution_id == other.evolution_id,
            .Generic => @panic("unimplemented"), // TODO
            .Primitive => |self_val| other.contents == .Primitive and switch (self_val) {
                .Bounded => |sval| {
                    const comparator = switch (other.contents.Primitive) {
                        .Bounded => @enumToInt(other.contents.Primitive.Bounded),
                        .Unbounded => @enumToInt(other.contents.Primitive.Unbounded),
                    };
                    if (comparator == @enumToInt(sval)) return null;
                    return false;
                },
                .Unbounded => |sval| switch (other.contents.Primitive) {
                    .Unbounded => |oval| sval == oval,
                    // The usecase for self being unbounded but other being
                    // bounded is yet-unknown but the code is fairly trivial
                    // to write so we'll support it... for now?
                    .Bounded => |oval| @enumToInt(sval) == @enumToInt(oval),
                },
            },
        };
    }
};

pub const MemberWord = struct {
    given_name: *Types.HeapedSymbol,
    signature: WordSignature,
};

pub const ShapeContents = union(enum) {
    Empty,
    /// Shapes are purely metadata for primitive root types: the underlying
    /// value isn't "boxed" into a shape struct, instead, Objects with a
    /// null shape pointer are assumed to be the respective root shape
    /// for the underlying primitive type in memory. In other words, a
    /// pair of {null, 8u} is known to be an UnsignedInt type on the Gale
    /// side, and only one UnsignedInt shape struct will ever exist in
    /// memory (cached in the Runtime)
    Primitive: union(enum) {
        // These MUST be sorted IDENTICALLY to the Unbounded enum below!!
        const Bounded = enum(u4) {
            Boolean,
            CharSlice,
            Float,
            SignedInt,
            UnsignedInt,
        };

        // These MUST be sorted IDENTICALLY to the Bounded enum above!!
        const Unbounded = enum(u4) {
            Boolean,
            CharSlice,
            Float,
            SignedInt,
            UnsignedInt,
        };

        /// These are the most general cases: *any* boolean value, *any*
        /// string, *any* uint, etc.
        Unbounded: Unbounded,

        /// These are special cases that aren't yet implemented (TODO: update
        /// this comment when they are...): a word can specify that it accepts
        /// exactly the integer "2", or perhaps only the string "foo". These
        /// word signatures are then represented with a non-evolved clone of
        /// the shape, with the Unbounded enum member converted to a Bounded
        /// member, which will trigger the slower validity checks during type
        /// checking. This concept has a fancy name in type system theory, but
        /// I'm offline right now and can't look it up. This entire type system
        /// is being written by the seat of my pants, I'm not an academic :)
        ///
        /// Bounded shapes *must* fulfill what is at runtime known as the
        /// BoundsCheckable shape, which includes an in-bounds? word with
        /// signature ( {Unbounded Analogue Shape} <- Boolean )
        Bounded: Bounded,

        // Why, you might ask, did I just represent 10 states as 2x5 enums rather
        // than a 1x10? Because it makes checking just a *bit* easier to read
        // later: rather than checking if something is a BoundedA || BoundedB ||
        // etc, I can check which family they belong to first, and then match
        // the inner "type".

        comptime {
            // Since we depend on these integer values matching as part of
            // `Shape.compatible_with`, let's paranoically ensure we're not
            // going to trigger some unsafe, undefined (or incorrectly-defined)
            // behavior later...
            std.debug.assert(@enumToInt(Unbounded.Boolean) == @enumToInt(Bounded.Boolean));
            std.debug.assert(@enumToInt(Unbounded.CharSlice) == @enumToInt(Bounded.CharSlice));
            std.debug.assert(@enumToInt(Unbounded.Float) == @enumToInt(Bounded.Float));
            std.debug.assert(@enumToInt(Unbounded.SignedInt) == @enumToInt(Bounded.SignedInt));
            std.debug.assert(@enumToInt(Unbounded.UnsignedInt) == @enumToInt(Bounded.UnsignedInt));
        }
    },
    Generic: Generic,
};

pub const Generic = union(enum) {
    /// Small generics are inlined for quicker lookups.
    ///
    /// Null pointers in .shapes are ambiguous (thus the addition of .slots):
    ///
    /// - if idx < .slots, null pointers reflect unfilled slots. It's expected
    ///   (though not yet enforced elsewhere) that the number of unfilled slots
    ///   will always be either 0, or .slots, never anything in between. In other
    ///   words, MyShape<_, _> is valid (albeit useless for anything except
    ///   pattern matching any MyShape), MyShape<MyThing, MyError> is valid
    ///   (and is thus the fully-populated and instantiable form of MyShape),
    ///   but MyShape<MyThing, _> is not (yet? TODO determine if this decision
    ///   should change).
    ///
    /// - if idx >= .slots, null pointers are unused memory and are out of
    ///   bounds
    SizeBounded: struct {
        slots: usize,
        shapes: [NUM_INLINED_SHAPES_IN_GENERICS]?*Shape,
    },
    /// Larger generics (since the maximum number of member types within a
    /// generic is unbounded) have to be heap-allocated in their own space.
    SizeUnbounded: []?*Shape,
};

test {
    std.testing.refAllDeclsRecursive(@This());
}
