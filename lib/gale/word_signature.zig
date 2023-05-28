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
    /// Boolean <-/-> ), stores the Shapes it will consume
    PurelyConsuming: []*Shape,
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

    pub fn compatible_with(self: *Self, other: *Self) bool {
        if (self == other) return true;

        return switch (self.*) {
            .SideEffectary => other.* == .SideEffectary,
            .Nullary => other.* == .Nullary and self.nullaries_compatible(other),
            .PurelyConsuming => other.* == .PurelyConsuming and self.consuming_compatible(other),
            .PurelyAdditive => other.* == .PurelyAdditive and self.additive_compatible(other),
            .Mutative => other.* == .Mutative and self.mutative_compatible(other),
        };
    }

    test "two words which solely generate side effects are compatible" {
        var word1: Self = Self.SideEffectary;
        var word2: Self = Self.SideEffectary;
        try expect(word1.compatible_with(&word2));
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
};

test {
    std.testing.refAllDeclsRecursive(@This());
}
