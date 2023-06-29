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
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const InternalError = @import("./internal_error.zig").InternalError;
const Types = @import("./types.zig");
const _shape = @import("./shape.zig");
const Shape = _shape.Shape;

const CATCHALL_HOLDING_TYPE = _shape.CATCHALL_HOLDING_TYPE;
const HIGHEST_CATCHALL = std.math.maxInt(CATCHALL_HOLDING_TYPE);

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

    /// Only this many incompatibilities on the "left" or "right" sides of
    /// a WordSignature will be enumerated, to save memory. This allows
    /// striking a balance between reducing the number of "round trips"
    /// a developer needs to make between their linter and their source
    /// file when fixing a signature, and memory usage (since our report
    /// arrays must be size-bounded to avoid allocating a heaped array).
    pub const MAX_INCOMPATIBILIY_INDICIES_REPORTED = 5;

    const SCR = SignatureCompatibilityResult;
    const SIR = SignatureIncompatibilityReason;

    pub const SignatureCompatibilityResult = union(enum(u1)) {
        Compatible,
        Incompatible: SignatureIncompatibilityReason,

        /// Downcast into a boolean, losing the SignatureIncompatibilityReason
        /// in the process. This is primarily useful in tests for context-less
        /// quick-failing operations, and should almost never be used in any
        /// context that could be visible to an end user, as valuable debugging
        /// information gets lost.
        pub fn as_bool_lossy(self: *const @This()) bool {
            return self.* == @This().Compatible;
        }
    };

    pub const SignatureIncompatibilityReason = union(enum) {
        Incomparable,
        UnderlyingShapesIncompatible: struct {
            left: ?UnderlyingShapesIncompatible = null,
            right: ?UnderlyingShapesIncompatible = null,
        },
        DisparateShapeCount: DisparateShapeCountSidedness,
        CatchAllMultipleResolutionCandidates: CATCHALL_HOLDING_TYPE,
    };

    pub const UnderlyingShapesIncompatible = [MAX_INCOMPATIBILIY_INDICIES_REPORTED]?UnderlyingShapeIncompatibility;

    pub const UnderlyingShapeIncompatibility = struct {
        index: usize,
        reason: Shape.ShapeIncompatibilityReason,
    };

    pub const DisparateShapeCountSidedness = struct {
        left: bool = false,
        right: bool = false,
    };

    /// Answering the question, "can this word be used here?", for example when
    /// passing a word as an argument to another word, or for fulfilling shape
    /// contracts.
    pub fn compatible_with(self: *Self, other: *Self) SCR {
        if (self == other or std.meta.eql(self.*, other.*)) return SCR.Compatible;
        if (std.meta.activeTag(self.*) != std.meta.activeTag(other.*)) return SCR{ .Incompatible = .Incomparable };

        return switch (self.*) {
            .SideEffectary => unreachable, // by way of std.meta.eql above
            .Nullary => self.nullaries_compatible(other),
            .NullaryTerminal => SCR.Compatible,
            .PurelyConsuming, .ConsumingTerminal => self.consuming_compatible(other),
            .PurelyAdditive => self.additive_compatible(other),
            .Mutative => self.mutative_compatible(other),
        };
    }

    const IncompatibilitySidedness = enum {
        Left,
        Right,
    };

    const IncompatibilityReport = struct {
        incompatibilities: ?SIR,
        generics_resolved: ?[HIGHEST_CATCHALL]?*Shape,
    };

    // TODO: Better docstring
    /// Slices MUST be the same length or you will get OOB panics!
    fn detect_incompatibilities(
        self_shapes: []*Shape,
        other_shapes: []*Shape,
        side: IncompatibilitySidedness,
    ) IncompatibilityReport {
        if (self_shapes.len != other_shapes.len) {
            return IncompatibilityReport{
                .generics_resolved = null,
                .incompatibilities = SIR{ .DisparateShapeCount = switch (side) {
                    .Left => .{ .left = true },
                    .Right => .{ .right = true },
                } },
            };
        }

        var any_generics_resolved = false;
        var degenericized_shapes: [HIGHEST_CATCHALL]?*Shape = .{null} ** HIGHEST_CATCHALL;
        var indicies_with_errors: UnderlyingShapesIncompatible = .{null} ** MAX_INCOMPATIBILIY_INDICIES_REPORTED;
        var err_idx: usize = 0;
        for (self_shapes) |arg, idx| {
            switch (arg.compatible_with(other_shapes[idx])) {
                .Compatible => continue,
                .Incompatible => |reason| {
                    indicies_with_errors[err_idx] = .{ .index = idx, .reason = reason };
                    err_idx += 1;

                    if (err_idx == MAX_INCOMPATIBILIY_INDICIES_REPORTED) break;
                },
                .Indeterminate => {
                    switch (arg.contents) {
                        .Empty => unreachable,
                        .Primitive => @panic("unimplemented"), // TODO
                        .CatchAll => |ca| {
                            if (degenericized_shapes[ca]) |ds| {
                                if (ds != other_shapes[idx]) {
                                    indicies_with_errors[err_idx] = .{
                                        .index = idx,
                                        .reason = Shape.ShapeIncompatibilityReason.CatchAllMultipleResolutionCandidates,
                                    };
                                    err_idx += 1;

                                    if (err_idx == MAX_INCOMPATIBILIY_INDICIES_REPORTED) break;
                                }
                            } else {
                                degenericized_shapes[ca] = other_shapes[idx];
                                any_generics_resolved = true;
                            }
                        },
                    }
                },
            }
        }

        return IncompatibilityReport{
            .generics_resolved = if (any_generics_resolved) degenericized_shapes else null,
            .incompatibilities = if (err_idx == 0) null else SIR{
                .UnderlyingShapesIncompatible = switch (side) {
                    .Left => .{ .left = indicies_with_errors },
                    .Right => .{ .right = indicies_with_errors },
                },
            },
        };
    }

    fn nullaries_compatible(self: *Self, other: *Self) SCR {
        const report = detect_incompatibilities(
            self.Nullary,
            other.Nullary,
            .Right,
        );

        return if (report.incompatibilities) |ic| SCR{ .Incompatible = ic } else SCR.Compatible;
    }

    fn consuming_compatible(self: *Self, other: *Self) SCR {
        const report = detect_incompatibilities(
            self.PurelyConsuming,
            other.PurelyConsuming,
            .Left,
        );

        return if (report.incompatibilities) |ic| SCR{ .Incompatible = ic } else SCR.Compatible;
    }

    fn dual_sided_contextual_compatibility(left: IncompatibilityReport, right: IncompatibilityReport) SCR {
        if (left.incompatibilities) |lic| {
            if (right.incompatibilities) |ric| {
                return SCR{
                    .Incompatible = SIR{ .UnderlyingShapesIncompatible = .{
                        .left = lic.UnderlyingShapesIncompatible.left,
                        .right = ric.UnderlyingShapesIncompatible.right,
                    } },
                };
            }
            return SCR{ .Incompatible = lic };
        }

        if (right.incompatibilities) |ric| return SCR{ .Incompatible = ric };

        if (left.generics_resolved) |lg| {
            if (right.generics_resolved) |rg| {
                for (lg) |gen, idx| {
                    if (gen != rg[idx]) {
                        return SCR{ .Incompatible = SIR{
                            .CatchAllMultipleResolutionCandidates = @truncate(CATCHALL_HOLDING_TYPE, idx),
                        } };
                    }
                }
            }
        }

        return SCR.Compatible;
    }

    fn additive_compatible(self: *Self, other: *Self) SCR {
        return dual_sided_contextual_compatibility(
            detect_incompatibilities(
                self.PurelyAdditive.expects,
                other.PurelyAdditive.expects,
                .Left,
            ),
            detect_incompatibilities(
                self.PurelyAdditive.gives,
                other.PurelyAdditive.gives,
                .Right,
            ),
        );
    }

    fn mutative_compatible(self: *Self, other: *Self) SCR {
        return dual_sided_contextual_compatibility(
            detect_incompatibilities(
                self.Mutative.before,
                other.Mutative.before,
                .Left,
            ),
            detect_incompatibilities(
                self.Mutative.after,
                other.Mutative.after,
                .Right,
            ),
        );
    }

    // NOTE: These tests only test word *signature* compatibility. For tests
    // regarding "if the stack looks like X, is word Y legal to run?", see
    // lib/gale/type_system_tests.zig which is a series of integration tests
    // that set up an entire Runtime to simulate real world (ish) scenarios.

    test "SideEffectary: ( -> ) and ( -> ) are compatible" {
        var word1: Self = Self.SideEffectary;
        var word2: Self = Self.SideEffectary;
        try expect(word1.compatible_with(&word2).as_bool_lossy());
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

        try expect(word1.compatible_with(&word2).as_bool_lossy());
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

        // TODO: test *why* these words aren't compatible
        try expect(!word1.compatible_with(&word2).as_bool_lossy());
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

        // TODO: test *why* these words aren't compatible
        try expect(!word1.compatible_with(&word2).as_bool_lossy());
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

        // TODO: test *why* these words aren't compatible
        try expect(!word1.compatible_with(&word2).as_bool_lossy());

        // This is technically the more correct (and slightly less resource
        // intensive) way to represent ( -> ) anyway
        word2 = Self.SideEffectary;
        // TODO: test *why* these words aren't compatible
        try expect(!word1.compatible_with(&word2).as_bool_lossy());
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

        try expect(word1.compatible_with(&word2).as_bool_lossy());
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

        // TODO: test *why* these words aren't compatible
        try expect(!word1.compatible_with(&word2).as_bool_lossy());
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

        // TODO: test *why* these words aren't compatible
        try expect(!word1.compatible_with(&word2).as_bool_lossy());
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

        // TODO: test *why* these words aren't compatible
        try expect(!word1.compatible_with(&word2).as_bool_lossy());
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

        // TODO: test *why* these words aren't compatible
        try expect(!word1.compatible_with(&word2).as_bool_lossy());
    }

    test "PurelyConsuming (generics): ( @1 -> ) and ( Boolean -> ) are compatible" {
        const word1_takes = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_takes);
        const word2_takes = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word2_takes);

        const catchall_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(catchall_shape);
        catchall_shape.* = Shape.new_containing_catchall(1);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);

        word1_takes[0] = catchall_shape;
        word2_takes[0] = boolean_shape;

        var word1 = Self{ .PurelyConsuming = word1_takes };
        var word2 = Self{ .PurelyConsuming = word2_takes };

        try expect(word1.compatible_with(&word2).as_bool_lossy());
    }

    test "PurelyConsuming (generics): ( @1 @1 -> ) and ( Boolean Boolean -> ) are compatible" {
        const word1_takes = try testAllocator.alloc(*Shape, 2);
        defer testAllocator.free(word1_takes);
        const word2_takes = try testAllocator.alloc(*Shape, 2);
        defer testAllocator.free(word2_takes);

        const catchall_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(catchall_shape);
        catchall_shape.* = Shape.new_containing_catchall(1);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);

        word1_takes[0] = catchall_shape;
        word1_takes[1] = catchall_shape;
        word2_takes[0] = boolean_shape;
        word2_takes[1] = boolean_shape;

        var word1 = Self{ .PurelyConsuming = word1_takes };
        var word2 = Self{ .PurelyConsuming = word2_takes };

        try expect(word1.compatible_with(&word2).as_bool_lossy());
    }

    test "PurelyConsuming (generics): ( @1 @2 @1 -> ) and ( Boolean UnsignedInt Boolean -> ) are compatible" {
        const word1_takes = try testAllocator.alloc(*Shape, 3);
        defer testAllocator.free(word1_takes);
        const word2_takes = try testAllocator.alloc(*Shape, 3);
        defer testAllocator.free(word2_takes);

        const catchall1_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(catchall1_shape);
        catchall1_shape.* = Shape.new_containing_catchall(1);

        const catchall2_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(catchall2_shape);
        catchall2_shape.* = Shape.new_containing_catchall(2);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);

        const unsigned_int_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(unsigned_int_shape);
        unsigned_int_shape.* = Shape.new_containing_primitive(.Unbounded, .UnsignedInt);

        word1_takes[0] = catchall1_shape;
        word1_takes[1] = catchall2_shape;
        word1_takes[2] = catchall1_shape;
        word2_takes[0] = boolean_shape;
        word2_takes[1] = unsigned_int_shape;
        word2_takes[2] = boolean_shape;

        var word1 = Self{ .PurelyConsuming = word1_takes };
        var word2 = Self{ .PurelyConsuming = word2_takes };

        try expect(word1.compatible_with(&word2).as_bool_lossy());
    }

    test "PurelyConsuming (generics): ( String -> ) and ( @1 -> ) are incompatible" {
        const word1_takes = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_takes);
        const word2_takes = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word2_takes);

        const catchall_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(catchall_shape);
        catchall_shape.* = Shape.new_containing_catchall(1);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);

        word1_takes[0] = boolean_shape;
        word2_takes[0] = catchall_shape;

        var word1 = Self{ .PurelyConsuming = word1_takes };
        var word2 = Self{ .PurelyConsuming = word2_takes };

        // TODO: test *why* these words aren't compatible
        try expect(!word1.compatible_with(&word2).as_bool_lossy());
    }

    test "PurelyConsuming (generics): ( @1 @1 -> ) and ( Boolean UnsignedInt -> ) are incompatible" {
        const word1_takes = try testAllocator.alloc(*Shape, 2);
        defer testAllocator.free(word1_takes);
        const word2_takes = try testAllocator.alloc(*Shape, 2);
        defer testAllocator.free(word2_takes);

        const catchall_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(catchall_shape);
        catchall_shape.* = Shape.new_containing_catchall(1);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);

        const unsigned_int_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(unsigned_int_shape);
        unsigned_int_shape.* = Shape.new_containing_primitive(.Unbounded, .UnsignedInt);

        word1_takes[0] = catchall_shape;
        word1_takes[1] = catchall_shape;
        word2_takes[0] = boolean_shape;
        word2_takes[1] = unsigned_int_shape;

        var word1 = Self{ .PurelyConsuming = word1_takes };
        var word2 = Self{ .PurelyConsuming = word2_takes };

        // TODO: test *why* these words aren't compatible
        try expect(!word1.compatible_with(&word2).as_bool_lossy());
    }

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

        try expect(word1.compatible_with(&word2).as_bool_lossy());
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

        try expect(word1.compatible_with(&word2).as_bool_lossy());
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

        // TODO: test *why* these words aren't compatible
        try expect(!word1.compatible_with(&word2).as_bool_lossy());
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

        try expect(word1.compatible_with(&word2).as_bool_lossy());
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

        // TODO: test *why* these words aren't compatible
        try expect(!word1.compatible_with(&word2).as_bool_lossy());
        try expect(!word2.compatible_with(&word1).as_bool_lossy());
    }

    test "Mutative: ( @1 -> @1 ) and ( Boolean -> UnsignedInt ) are incompatible" {
        const word1_before = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_before);
        const word2_before = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word2_before);
        const word1_after = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word1_after);
        const word2_after = try testAllocator.alloc(*Shape, 1);
        defer testAllocator.free(word2_after);

        const catchall_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(catchall_shape);
        catchall_shape.* = Shape.new_containing_catchall(1);

        const boolean_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(boolean_shape);
        boolean_shape.* = Shape.new_containing_primitive(.Unbounded, .Boolean);
        const unsigned_int_shape = try testAllocator.create(Shape);
        defer testAllocator.destroy(unsigned_int_shape);
        unsigned_int_shape.* = Shape.new_containing_primitive(.Unbounded, .UnsignedInt);

        word1_before[0] = catchall_shape;
        word2_before[0] = boolean_shape;
        word1_after[0] = catchall_shape;
        word2_after[0] = unsigned_int_shape;

        var word1 = Self{ .Mutative = .{ .before = word1_before, .after = word1_after } };
        var word2 = Self{ .Mutative = .{ .before = word2_before, .after = word2_after } };

        // TODO: test *why* these words aren't compatible
        try expect(!word1.compatible_with(&word2).as_bool_lossy());
    }
};

test {
    std.testing.refAllDeclsRecursive(@This());
}
