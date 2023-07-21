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

    Array: *Types.HeapedArray,
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
            .Array => |inner| {
                // First, we need to deref and kill all the objects stored
                // in this array, garbage collecting the inner contents as
                // necessary.
                //
                // Using ? here because if we have an Rc with no contents at
                // this point, something has gone horribly, horribly wrong, and
                // panicking the thread is appropriate.
                for (inner.value.?.items) |_it| {
                    var it = _it;
                    it.deinit(alloc);
                }

                // Now we can toss this Object and the ArrayList stored within.
                // Passing alloc here is necessary by type signature only; it
                // won't be used (since ArrayList is a ManagedStruct).
                _ = inner.decrement_and_prune(.DeinitInner, alloc);
            },
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
            .Array => |rc| try rc.increment(),
            .Boolean, .Float, .SignedInt, .UnsignedInt => {},
            .String => |rc| try rc.increment(),
            .Symbol => |rc| try rc.increment(),
            .Opaque => |rc| try rc.increment(),
            .Word => |rc| try rc.increment(),
        }

        return self;
    }

    /// Raise an `InternalError.TypeError` if this object is not the same primitive
    /// kind as `other`.
    ///
    /// Returns `self` after this check to allow for chaining.
    pub fn assert_same_kind_as(self: *Self, other: *Self) InternalError!*Self {
        if (std.meta.activeTag(self.*) != std.meta.activeTag(other.*)) {
            return InternalError.TypeError;
        }

        return self;
    }
};

test {
    std.testing.refAllDecls(@This());
}
