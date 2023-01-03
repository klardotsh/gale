// gluumy's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

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
            .Boolean, .UnsignedInt, .SignedInt => {},
            .String, .Symbol => |inner| {
                _ = inner.decrement_and_prune(.FreeInnerDestroySelf, alloc);
            },
            // TODO: how to handle this?
            .Opaque => unreachable,
            .Word => |inner| {
                _ = inner.decrement_and_prune(.DeinitInnerWithAllocDestroySelf, alloc);
            },
        }
    }

    /// Indicate another reference to the underlying data has been made in
    /// userspace, which is a no-op for "unboxed" types, and increments the
    /// internal `strong_count` for the "boxed"/managed types. Returns self
    /// after such internal mutations have been made, mostly for chaining
    /// ergonomics.
    pub fn ref(self: Self) !Self {
        switch (self) {
            .Boolean, .UnsignedInt, .SignedInt => {},
            .String => |rc| try rc.increment(),
            .Symbol => |rc| try rc.increment(),
            .Opaque => |rc| try rc.increment(),
            .Word => |rc| try rc.increment(),
        }

        return self;
    }

    /// Raise an `InternalError.TypeError` if this Object is not of `kind`,
    /// which must be a member of the Object enum (eg. `.Boolean`).
    pub fn assert_is_kind(self: *Self, comptime kind: anytype) InternalError!void {
        if (@as(Self, self.*) != kind) {
            return InternalError.TypeError;
        }
    }

    /// Determine whether two Objects of the same kind (same member of the
    /// Object enum) are the same, raising `InternalError.TypeError` otherwise.
    /// For unboxed types, this check is against the underlying value (eg. `1
    /// == 1`). For boxed types (behind `Rc(_)`), this check is against the
    /// pointer (in other words, do these two Objects point to the same
    /// underlying Rc?).
    pub fn eq(self: *Self, other: *Self) !bool {
        if (self == other) {
            return true;
        }

        return switch (self.*) {
            .Boolean => |self_val| switch (other.*) {
                .Boolean => |other_val| self_val == other_val,
                else => InternalError.TypeError,
            },
            .UnsignedInt => |self_val| switch (other.*) {
                .UnsignedInt => |other_val| self_val == other_val,
                else => InternalError.TypeError,
            },
            .SignedInt => |self_val| switch (other.*) {
                .SignedInt => |other_val| self_val == other_val,
                else => InternalError.TypeError,
            },
            .String => |self_val| switch (other.*) {
                .String => |other_val| self_val == other_val,
                else => InternalError.TypeError,
            },
            .Symbol => |self_val| switch (other.*) {
                .Symbol => |other_val| self_val == other_val,
                else => InternalError.TypeError,
            },
            .Opaque => |self_val| switch (other.*) {
                .Opaque => |other_val| self_val == other_val,
                else => InternalError.TypeError,
            },
            .Word => |self_val| switch (other.*) {
                .Word => |other_val| self_val == other_val,
                else => InternalError.TypeError,
            },
        };
    }
};

test {
    std.testing.refAllDecls(@This());
}
