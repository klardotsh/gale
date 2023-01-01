// gluumy's canonical implementation and standard library is released to the
// public domain (or your jurisdiction's closest legal equivalent) under the
// Creative Commons Zero 1.0 dedication, distributed alongside this source in a
// file called COPYING.

const std = @import("std");
const Allocator = std.mem.Allocator;

const InternalError = @import("./internal_error.zig").InternalError;
const Types = @import("./types.zig");

/// Within our Stack we can store a few primitive types:
pub const Object = union(enum) {
    const Self = @This();

    Boolean: bool,
    UnsignedInt: usize,
    SignedInt: isize,
    String: Types.GluumyString,
    Symbol: Types.GluumySymbol,
    /// Opaque represents a blob of memory that is left to userspace to manage
    /// manually. TODO more docs here.
    Opaque: Types.GluumyOpaque,
    Word: Types.GluumyWord,

    pub fn deinit(self: *Self, alloc: Allocator) void {
        switch (self.*) {
            Self.Boolean, Self.UnsignedInt, Self.SignedInt => {},
            Self.String, Self.Symbol => |inner| {
                _ = inner.decrement_and_prune_free_inner(alloc);
            },
            // TODO: how to handle this?
            Self.Opaque => unreachable,
            Self.Word => |inner| {
                _ = inner.decrement_and_prune_deinit_with_alloc_inner(alloc);
            },
        }
    }

    pub fn assert_is_kind(self: *Self, comptime kind: anytype) InternalError!void {
        if (@as(Self, self.*) != kind) {
            return InternalError.TypeError;
        }
    }

    pub fn eq(self: *Self, other: *Self) !bool {
        if (self == other) {
            return true;
        }

        return switch (self.*) {
            Self.Boolean => |self_val| switch (other.*) {
                Self.Boolean => |other_val| self_val == other_val,
                else => error.CannotCompareDisparateTypes,
            },
            Self.UnsignedInt => |self_val| switch (other.*) {
                Self.UnsignedInt => |other_val| self_val == other_val,
                else => error.CannotCompareDisparateTypes,
            },
            Self.SignedInt => |self_val| switch (other.*) {
                Self.SignedInt => |other_val| self_val == other_val,
                else => error.CannotCompareDisparateTypes,
            },
            Self.String => |self_val| switch (other.*) {
                Self.String => |other_val| self_val == other_val,
                else => error.CannotCompareDisparateTypes,
            },
            Self.Symbol => |self_val| switch (other.*) {
                Self.Symbol => |other_val| self_val == other_val,
                else => error.CannotCompareDisparateTypes,
            },
            Self.Opaque => |self_val| switch (other.*) {
                Self.Opaque => |other_val| self_val == other_val,
                else => error.CannotCompareDisparateTypes,
            },
            Self.Word => |self_val| switch (other.*) {
                Self.Word => |other_val| self_val == other_val,
                else => error.CannotCompareDisparateTypes,
            },
        };
    }
};
