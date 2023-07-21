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

const builtin = @import("builtin");

const InternalError = @import("./internal_error.zig").InternalError;
const Types = @import("./types.zig");

// TODO: allow override in build.zig
const RC_ALLOW_INIT_GT0: bool = false;

pub fn Rc(comptime T: type) type {
    return struct {
        const no_valid_innerkind_msg = "Could not determine an InnerKind for value's type: " ++ @typeName(T);
        const inner_kind = switch (@typeInfo(T)) {
            .Pointer => |pointer| switch (pointer.size) {
                .One => .SinglePointer,
                .Slice => .SlicePointer,
                else => @compileError(no_valid_innerkind_msg),
            },
            .Struct => |container| strct: {
                // TODO: See if this is the only differentiator worth caring
                // about, or if we should also factor things like the name of
                // the field in. Or maybe we need a wrapper type rather than
                // metaprogramming magic, who knows.
                for (container.fields) |field| if (field.field_type == Allocator) {
                    break :strct .ManagedStruct;
                };
                break :strct .Struct;
            },
            else => @compileError(no_valid_innerkind_msg),
        };

        pub const PruneMode = switch (inner_kind) {
            .SinglePointer => enum {
                DestroyInner,
                DestroyInnerAndSelf,
            },
            .SlicePointer => enum {
                FreeInner,
                FreeInnerDestroySelf,
            },
            .Struct => enum {
                DeinitInnerWithAlloc,
                DeinitInnerWithAllocDestroySelf,
            },
            .ManagedStruct => enum { DeinitInner },
            else => @compileError("No valid PruneModes exist for value's type: " ++ @typeName(T)),
        };

        const Self = @This();
        const RefCount = std.atomic.Atomic(u16);

        strong_count: RefCount,
        value: ?T,

        /// Initialize an Rc(T) with no references. This is almost always the
        /// correct default, but if you're absolutely sure it's not, see
        /// `init_referenced`.
        pub fn init(value: ?T) Self {
            return Self{
                .strong_count = RefCount.init(0),
                .value = value,
            };
        }

        /// Initialize an Rc(T) which is assumed to already have a reference.
        /// This should almost never be used directly outside of tests, as most
        /// Stack and/or Object operations assume an Rc(_) starts with no
        /// references (since strong_count really refers to the number of
        /// gale-side references, and is not meant to be a generic zig garbage
        /// collector).
        pub fn init_referenced(value: ?T) Self {
            if (!builtin.is_test and !RC_ALLOW_INIT_GT0) {
                @compileError(@typeName(Self) ++ ".init_referenced called outside of unit tests (override with build arg RC_ALLOW_INIT_GT0)");
            }

            return Self{
                .strong_count = RefCount.init(1),
                .value = value,
            };
        }

        /// Return whether or not this object is considered "dead", in that it
        /// is no longer referenced and contains only a null value. This is
        /// *not* the same logic used by `decrement_and_prune`, but can be used
        /// to build multi-step prune-then-destroy garbage collection passes.
        pub fn dead(self: *Self) bool {
            const no_refs = self.strong_count.load(.Acquire) == 0;
            const no_data = self.value == null;

            if (no_refs and !no_data) {
                std.debug.panic("partially-dead Rc@{d}: no refs, but data still exists", .{&self});
            }

            if (!no_refs and no_data) {
                std.debug.panic("improperly killed Rc@{d}: data has been wiped, but references remain", .{&self});
            }

            return no_refs and no_data;
        }

        /// Increment the number of references to this Rc.
        pub fn increment(self: *Self) InternalError!void {
            if (self.value == null) return InternalError.AttemptedResurrectionOfExhaustedRc;
            _ = self.strong_count.fetchAdd(1, .Monotonic);
        }

        /// Returned boolean reflects the livelihood of the object after this
        /// decrement: if false, it is assumed to be safe for callers to free
        /// the underlying data.
        // TODO: flip this boolean: the ergonomics are stupid after a while of
        // actually using this, and there's constant NOT-ing being done to
        // coerce this back into the "right" question's answer ("is this object
        // freeable?" "yes").
        pub fn decrement(self: *Self) bool {
            // Release ensures code before unref() happens-before the count is
            // decremented as dropFn could be called by then.
            if (self.strong_count.fetchSub(1, .Release) == 1) {
                // Acquire ensures count decrement and code before previous
                // unrefs()s happens-before we null the field.
                self.strong_count.fence(.Acquire);
                self.value = null;
                return false;
            }

            return true;
        }

        /// Decrement strong count by one and prune data in varying ways.
        /// Returns whether pruning was done: if true, the inner data of this
        /// Rc has been freed and will segfault if accessed, and depending on
        /// PruneMode, the Rc itself may no longer be valid, either.
        ///
        /// In general, PruneMode.*Self are the correct modes if this Rc is
        /// heap-allocated with the Runtime's allocator, and the other options
        /// are good fits for stack-allocated Rcs, or those allocated by
        /// allocators the Runtime does not own (perhaps, HeapMap or
        /// ArrayList), for example when clearing inner data from a
        /// valueIterator().next().value - the pointer itself is owned by the
        /// ArrayList, but the inner datastructures are generally gale-owned
        /// and will leak if not torn down correctly.
        ///
        /// Since PruneModes are comptime-generated enums, it is not possible
        /// to use an outright invalid mode for the underlying value's type,
        /// say, .DestroyInner on a slice pointer (for which .FreeInner would
        /// be the correct instruction).
        pub fn decrement_and_prune(self: *Self, prune_mode: PruneMode, alloc: Allocator) bool {
            var inner = self.value.?;
            const is_dead = !self.decrement();

            // TODO: since strings and symbols are interned to Runtime, right
            // now they will just leak until the Runtime is deinit()-ed. Unsure
            // whether this method should go poke Runtime to clean up its
            // intern table (and then almost certainly call this function
            // itself), or if Runtime should have some sort of mark-and-sweep
            // process that periodically finds interned strings and symbols for
            // which it holds the only reference. I'm leaving this comment
            // *here* because it's the most localized place I can think to put
            // it, the top of Rc() is probably not a great fit.

            // TODO: handle nulls safely, which will require plumbing an
            // InternalError up many stacks...
            if (is_dead) switch (inner_kind) {
                .SinglePointer => switch (prune_mode) {
                    .DestroyInner => alloc.destroy(inner),
                    .DestroyInnerAndSelf => {
                        alloc.destroy(inner);
                        alloc.destroy(self);
                    },
                },
                .SlicePointer => switch (prune_mode) {
                    .FreeInner => alloc.free(inner),
                    .FreeInnerDestroySelf => {
                        alloc.free(inner);
                        alloc.destroy(self);
                    },
                },
                .Struct => switch (prune_mode) {
                    .DeinitInnerWithAlloc => inner.deinit(alloc),
                    .DeinitInnerWithAllocDestroySelf => {
                        inner.deinit(alloc);
                        alloc.destroy(self);
                    },
                },
                .ManagedStruct => switch (prune_mode) {
                    .DeinitInner => inner.deinit(),
                },
                else => unreachable,
            };

            return is_dead;
        }
    };
}

test "Rc(u8): simple set, increments, decrements, and prune" {
    const SharedStr = Types.HeapedString;
    const hello_world = "Hello World!";
    var str = try testAllocator.alloc(u8, hello_world.len);
    std.mem.copy(u8, str[0..], hello_world);
    var shared_str = try testAllocator.create(SharedStr);
    shared_str.* = SharedStr.init_referenced(str);

    try std.testing.expectEqualStrings(hello_world, shared_str.value.?);
    try expect(shared_str.strong_count.load(.Acquire) == 1);
    try shared_str.increment();
    try expect(shared_str.strong_count.load(.Acquire) == 2);
    try expect(!shared_str.decrement_and_prune(.FreeInnerDestroySelf, testAllocator));
    try expect(shared_str.strong_count.load(.Acquire) == 1);

    // This last assertion is testing a lot of things in one swing, but is a
    // realistic usecase: given that we have one remaining reference, decrement
    // *again*, leaving us with no remaining references, and collect garbage by
    // freeing both the underlying u8 slice *and* the Rc itself. Thus, this
    // assertion is only part of the test's succeeding, the rest comes from
    // Zig's GeneralPurposeAllocator not warning us about any leaked memory
    // (which fails the tests at a higher level).
    try expect(shared_str.decrement_and_prune(.FreeInnerDestroySelf, testAllocator));
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
