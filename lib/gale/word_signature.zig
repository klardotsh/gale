// Gale's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testAllocator: Allocator = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const InternalError = @import("./internal_error.zig").InternalError;
const Types = @import("./types.zig");
const Shape = @import("./shape.zig").Shape;

/// An encoding of what a Word will do to the Stack.
pub const WordSignature = union(enum) {
    const Self = @This();

    /// ( -> ), usually side effects
    SideEffectary,
    /// ( <-/-> Boolean ), subset of PurelyAdditive
    Nullary: []*Shape,
    /// ( -> !!! ), a special case of Nullary, where it can never return
    /// (eg. panic/exit)
    NullaryTerminal,
    /// Boolean <-/-> ), stores the Shapes it will consume
    PurelyConsuming: []*Shape,
    /// ( Boolean -> !!! ), a special case of PurelyConsuming, where it can
    /// never return (eg. panic/exit)
    ConsumingTerminal: []*Shape,
    /// ( Boolean <- UnsignedInt ), stores the Shapes it expects to be on the
    /// Stack, and the Shapes it will add to it
    PurelyAdditive: struct {
        expects: []*Shape,
        gives: []*Shape,
    },
    /// ( Boolean -> UnsignedInt), stores the Shapes it expects to be on the
    /// Stack (and assumes all of them will be consumed unless otherwise
    /// noted), and the Shapes that will be on the Stack afterwards.
    Mutative: struct {
        before: []*Shape,
        after: []*Shape,
    },

    /// Answering the question, "can this word be used here?", for example when
    /// passing a word as an argument to another word, or for fulfilling shape
    /// contracts.
    pub fn compatible_with(self: *Self, other: *Self) bool {
        if (self == other) return true;

        return switch (self.*) {
            .SideEffectary => other.* == .SideEffectary,
            .Nullary => other.* == .Nullary and self.nullaries_compatible(other),
            .NullaryTerminal => @panic("unimplemented"), // TODO
            .PurelyConsuming => other.* == .PurelyConsuming and self.consuming_compatible(other),
            .ConsumingTerminal => @panic("unimplemented"), // TODO
            .PurelyAdditive => other.* == .PurelyAdditive and self.additive_compatible(other),
            .Mutative => other.* == .Mutative and self.mutative_compatible(other),
        };
    }

    // TODO: return context of which shape failed rather than just a boolean,
    // which provides zero debugging information and would be infuriating to
    // actually work with.
    inline fn nullaries_compatible(self: *Self, other: *Self) bool {
        if (self.Nullary.len != other.Nullary.len) return false;

        for (self.Nullary) |arg, idx| {
            return arg.compatible_with(other.Nullary[idx]) orelse false;
        }

        return true;
    }

    // TODO: return context of which shape failed rather than just a boolean,
    // which provides zero debugging information and would be infuriating to
    // actually work with.
    inline fn consuming_compatible(self: *Self, other: *Self) bool {
        if (self.PurelyConsuming.len != other.PurelyConsuming.len) return false;

        for (self.PurelyConsuming) |arg, idx| {
            return arg.compatible_with(other.PurelyConsuming[idx]) orelse false;
        }

        return true;
    }

    // TODO: return context of which shape failed rather than just a boolean,
    // which provides zero debugging information and would be infuriating to
    // actually work with.
    inline fn additive_compatible(self: *Self, other: *Self) bool {
        if (self.PurelyAdditive.expects.len != other.PurelyAdditive.expects.len or
            self.PurelyAdditive.gives.len != other.PurelyAdditive.gives.len)
        {
            return false;
        }

        for (self.PurelyAdditive.expects) |arg, idx| {
            if (arg.compatible_with(other.PurelyAdditive.expects[idx]) orelse false) continue;
            return false;
        }

        for (self.PurelyAdditive.gives) |arg, idx| {
            if (arg.compatible_with(other.PurelyAdditive.gives[idx]) orelse false) continue;
            return false;
        }

        return true;
    }

    // TODO: return context of which shape failed rather than just a boolean,
    // which provides zero debugging information and would be infuriating to
    // actually work with.
    inline fn mutative_compatible(self: *Self, other: *Self) bool {
        if (self.Mutative.before.len != other.Mutative.before.len or
            self.Mutative.after.len != other.Mutative.after.len)
        {
            return false;
        }

        for (self.Mutative.before) |arg, idx| {
            if (arg.compatible_with(other.Mutative.before[idx]) orelse false) continue;
            return false;
        }

        for (self.Mutative.after) |arg, idx| {
            if (arg.compatible_with(other.Mutative.after[idx]) orelse false) continue;
        }

        return true;
    }

    // NOTE: These tests only test word *signature* compatibility. For tests
    // regarding "if the stack looks like X, is word Y legal to run?", see
    // lib/gale/type_system_tests.zig which is a series of integration tests
    // that set up an entire Runtime to simulate real world (ish) scenarios.

    test "SideEffectary: ( -> ) and ( -> ) are compatible" {
        var word1: Self = Self.SideEffectary;
        var word2: Self = Self.SideEffectary;
        try expect(word1.compatible_with(&word2));
    }

    test "Nullary: ( -> Boolean ) and ( -> Boolean ) are compatible" {
        const word1_gives = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_gives);
        const word2_gives = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word2_gives);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);
        word1_gives[0] = boolean_shape;
        word2_gives[0] = boolean_shape;

        var word1 = Self{ .Nullary = word1_gives };
        var word2 = Self{ .Nullary = word2_gives };

        try expect(word1.compatible_with(&word2));
    }

    test "Nullary: ( -> Boolean ) and ( -> UnsignedInt ) are incompatible" {
        const word1_gives = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_gives);
        const word2_gives = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word2_gives);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);
        const unsigned_int_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(unsigned_int_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .UnsignedInt);
        word1_gives[0] = boolean_shape;
        word2_gives[0] = unsigned_int_shape;

        var word1 = Self{ .Nullary = word1_gives };
        var word2 = Self{ .Nullary = word2_gives };

        try expect(!word1.compatible_with(&word2));
    }

    test "Nullary: ( -> Boolean ) and ( -> Boolean Boolean ) are incompatible" {
        const word1_gives = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_gives);
        const word2_gives = try testAllocator.alloc(*Shape, 2);
        defer testAllocator.free(word2_gives);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);
        word1_gives[0] = boolean_shape;
        word2_gives[0] = boolean_shape;
        word2_gives[1] = boolean_shape;

        var word1 = Self{ .Nullary = word1_gives };
        var word2 = Self{ .Nullary = word2_gives };

        try expect(!word1.compatible_with(&word2));
    }

    test "Nullary/SideEffectary: ( -> Boolean ) and ( -> ) are incompatible" {
        const word1_gives = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_gives);
        const word2_gives = try testAllocator.alloc(*Shape, 0);
        defer testAllocator.free(word2_gives);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);
        word1_gives[0] = boolean_shape;

        var word1 = Self{ .Nullary = word1_gives };
        var word2 = Self{ .Nullary = word2_gives };

        try expect(!word1.compatible_with(&word2));

        // This is technically the more correct (and slightly less resource
        // intensive) way to represent ( -> ) anyway
        word2 = Self.SideEffectary;
        try expect(!word1.compatible_with(&word2));
    }

    test "PurelyConsuming: ( Boolean -> ) and ( Boolean -> ) are compatible" {
        const word1_takes = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_takes);
        const word2_takes = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word2_takes);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);
        word1_takes[0] = boolean_shape;
        word2_takes[0] = boolean_shape;

        var word1 = Self{ .PurelyConsuming = word1_takes };
        var word2 = Self{ .PurelyConsuming = word2_takes };

        try expect(word1.compatible_with(&word2));
    }

    test "PurelyConsuming: ( Boolean -> ) and ( UnsignedInt -> ) are incompatible" {
        const word1_takes = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_takes);
        const word2_takes = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word2_takes);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);
        const unsigned_int_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(unsigned_int_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .UnsignedInt);
        word1_takes[0] = boolean_shape;
        word2_takes[0] = unsigned_int_shape;

        var word1 = Self{ .PurelyConsuming = word1_takes };
        var word2 = Self{ .PurelyConsuming = word2_takes };

        try expect(!word1.compatible_with(&word2));
    }

    test "PurelyConsuming: ( Boolean -> ) and ( Boolean Boolean -> ) are incompatible" {
        const word1_takes = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_takes);
        const word2_takes = try testAllocator.alloc(*Shape, 2);
        defer testAllocator.free(word2_takes);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);
        word1_takes[0] = boolean_shape;
        word2_takes[0] = boolean_shape;
        word2_takes[1] = boolean_shape;

        var word1 = Self{ .PurelyConsuming = word1_takes };
        var word2 = Self{ .PurelyConsuming = word2_takes };

        try expect(!word1.compatible_with(&word2));
    }

    test "PurelyConsuming/Nullary: ( Boolean -> ) and  ( -> Boolean ) are incompatible" {
        const word1_takes = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_takes);
        const word2_gives = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word2_gives);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);
        word1_takes[0] = boolean_shape;
        word2_gives[0] = boolean_shape;

        var word1 = Self{ .PurelyConsuming = word1_takes };
        var word2 = Self{ .Nullary = word2_gives };

        try expect(!word1.compatible_with(&word2));
    }

    test "PurelyConsuming/SideEffectary: ( Boolean -> ) and ( -> ) are incompatible" {
        const word1_takes = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_takes);
        const word2_gives = try testAllocator.alloc(*Shape, 0);
        defer testAllocator.free(word2_gives);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);
        word1_takes[0] = boolean_shape;

        var word1 = Self{ .PurelyConsuming = word1_takes };
        var word2: Self = Self.SideEffectary;

        try expect(!word1.compatible_with(&word2));
    }

    // test "PurelyConsuming (generics): ( @1 -> ) and ( String -> ) are compatible, but the inverse is logically impossible" {
    //     const word1_takes = try testAllocator.alloc(*Shape, 1);
    //     defer testAllocator.free(word1_takes);
    //     const word2_takes = try testAllocator.alloc(*Shape, 1);
    //     defer testAllocator.free(word2_takes);

    //     const boolean_shape = try testAllocator.create(Shape);
    //     defer testAllocator.destroy(boolean_shape);
    //     boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);
    //     word1_takes[0] = boolean_shape;
    //     word2_takes[0] = boolean_shape;

    //     var word1 = Self{ .PurelyConsuming = word1_takes };
    //     var word2 = Self{ .PurelyConsuming = word2_takes };

    //     try expect(word1.compatible_with(&word2));
    // }

    test "PurelyAdditive: ( <- Boolean ) and ( <- Boolean ) are compatible" {
        const word1_expects = try testAllocator.alloc(*Shape, 0);
        defer testAllocator.free(word1_expects);
        const word2_expects = try testAllocator.alloc(*Shape, 0);
        defer testAllocator.free(word2_expects);
        const word1_gives = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_gives);
        const word2_gives = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word2_gives);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);
        word1_gives[0] = boolean_shape;
        word2_gives[0] = boolean_shape;

        var word1 = Self{ .PurelyAdditive = .{ .expects = word1_expects, .gives = word1_gives } };
        var word2 = Self{ .PurelyAdditive = .{ .expects = word2_expects, .gives = word2_gives } };

        try expect(word1.compatible_with(&word2));
    }

    test "PurelyAdditive: ( UnsignedInt <- Boolean ) and ( UnsignedInt <- Boolean ) are compatible" {
        const word1_expects = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_expects);
        const word2_expects = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word2_expects);
        const word1_gives = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_gives);
        const word2_gives = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word2_gives);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);
        const unsigned_int_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(unsigned_int_shape);
        unsigned_int_shape.* = Shape.new_containing_primitive(.Unbounded, .UnsignedInt);
        word1_expects[0] = unsigned_int_shape;
        word2_expects[0] = unsigned_int_shape;
        word1_gives[0] = boolean_shape;
        word2_gives[0] = boolean_shape;

        var word1 = Self{ .PurelyAdditive = .{ .expects = word1_expects, .gives = word1_gives } };
        var word2 = Self{ .PurelyAdditive = .{ .expects = word2_expects, .gives = word2_gives } };

        try expect(word1.compatible_with(&word2));
    }

    test "PurelyAdditive: ( <- Boolean ) and ( <- UnsignedInt ) are incompatible" {
        const word1_expects = try testAllocator.alloc(*Shape, 0);
        defer testAllocator.free(word1_expects);
        const word2_expects = try testAllocator.alloc(*Shape, 0);
        defer testAllocator.free(word2_expects);
        const word1_gives = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_gives);
        const word2_gives = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word2_gives);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);
        const unsigned_int_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(unsigned_int_shape);
        unsigned_int_shape.* = Shape.new_containing_primitive(.Unbounded, .UnsignedInt);
        word1_gives[0] = boolean_shape;
        word2_gives[0] = unsigned_int_shape;

        var word1 = Self{ .PurelyAdditive = .{ .expects = word1_expects, .gives = word1_gives } };
        var word2 = Self{ .PurelyAdditive = .{ .expects = word2_expects, .gives = word2_gives } };

        try expect(!word1.compatible_with(&word2));
    }

    test "Mutative: ( Boolean -> UnsignedInt ) and ( Boolean -> UnsignedInt ) are compatible" {
        const word1_before = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_before);
        const word2_before = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word2_before);
        const word1_after = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_after);
        const word2_after = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word2_after);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);
        const unsigned_int_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(unsigned_int_shape);
        unsigned_int_shape.* = Shape.new_containing_primitive(.Unbounded, .UnsignedInt);

        word1_before[0] = boolean_shape;
        word2_before[0] = boolean_shape;
        word1_after[0] = unsigned_int_shape;
        word2_after[0] = unsigned_int_shape;

        var word1 = Self{ .Mutative = .{ .before = word1_before, .after = word1_after } };
        var word2 = Self{ .Mutative = .{ .before = word2_before, .after = word2_after } };

        try expect(word1.compatible_with(&word2));
    }

    test "Mutative: ( Boolean Boolean -> UnsignedInt ) and ( Boolean -> UnsignedInt ) (and vice-versa) are incompatible" {
        const word1_before = try testAllocator.alloc(*Shape, 2);
        defer testAllocator.free(word1_before);
        const word2_before = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word2_before);
        const word1_after = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_after);
        const word2_after = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word2_after);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);
        const unsigned_int_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(unsigned_int_shape);
        unsigned_int_shape.* = Shape.new_containing_primitive(.Unbounded, .UnsignedInt);

        word1_before[0] = boolean_shape;
        word1_before[1] = boolean_shape;
        word2_before[0] = boolean_shape;
        word1_after[0] = unsigned_int_shape;
        word2_after[0] = unsigned_int_shape;

        var word1 = Self{ .Mutative = .{ .before = word1_before, .after = word1_after } };
        var word2 = Self{ .Mutative = .{ .before = word2_before, .after = word2_after } };

        try expect(!word1.compatible_with(&word2));
        try expect(!word2.compatible_with(&word1));
    }
};

test {
    std.testing.refAllDeclsRecursive(@This());
}
