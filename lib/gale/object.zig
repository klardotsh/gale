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

const InternalError = @import("./internal_error.zig").InternalError;
const Types = @import("./types.zig");

/// Within our Stack we can store a few primitive types:
pub const Object = union(enum) {
    const Self = @This();

    // TODO: primitive types should carry a preceding nullable pointer to their
    // respective Shape. For performance, null pointers here will represent
    // their base Shape, so [null, 8 as usize] is known to be an UnsignedInt,
    // but [Meters, 8 as usize] is known to be a Meters type of UnsignedInt

    Boolean: bool,
    Float: f64,
    /// Opaque represents a blob of memory that is left to userspace to manage
    /// manually. TODO more docs here.
    Opaque: *Types.HeapedOpaque,
    SignedInt: isize,
    String: *Types.HeapedString,
    Symbol: *Types.HeapedSymbol,
    UnsignedInt: usize,
    Word: *Types.HeapedWord,

    pub fn deinit(self: *Self, alloc: Allocator) void {
        switch (self.*) {
            .Boolean, .Float, .SignedInt, .UnsignedInt => {},
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
            .Boolean, .Float, .SignedInt, .UnsignedInt => {},
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
            .Float => |self_val| switch (other.*) {
                .Float => |other_val| self_val == other_val,
                else => InternalError.TypeError,
            },
            .SignedInt => |self_val| switch (other.*) {
                .SignedInt => |other_val| self_val == other_val,
                else => InternalError.TypeError,
            },
            .UnsignedInt => |self_val| switch (other.*) {
                .UnsignedInt => |other_val| self_val == other_val,
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
