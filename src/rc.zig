// gluumy's canonical implementation and standard library is released to the
// public domain (or your jurisdiction's closest legal equivalent) under the
// Creative Commons Zero 1.0 dedication, distributed alongside this source in a
// file called COPYING.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testAllocator: Allocator = std.testing.allocator;
const expect = std.testing.expect;

const InternalError = @import("./internal_error.zig").InternalError;
const Types = @import("./types.zig");

pub fn Rc(comptime T: type) type {
    return struct {
        const Self = @This();
        const RefCount = std.atomic.Atomic(u16);

        strong_count: RefCount,
        value: ?T,

        pub fn init(value: ?T) Self {
            return @This(){
                .strong_count = RefCount.init(1),
                .value = value,
            };
        }

        pub fn increment(self: *Self) !void {
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

        /// Decrement strong count by one and use the given allocator to
        /// destroy self if no references remain. Returns whether self was
        /// pruned or not: **if the return of this call is true, self now
        /// refers to freed memory and must never be used again**.
        ///
        /// By convention, this should never be used if self.value is of a
        /// pointer type: see `decrement_and_prune_destroy_inner` and
        /// `decrement_and_prune_free_inner` instead.
        pub fn decrement_and_prune(self: *Self, alloc: Allocator) bool {
            const dead = !self.decrement();
            if (dead) alloc.destroy(self);
            return dead;
        }

        /// Decrement strong count by one and use the given allocator to
        /// destroy both self *and* the underlying sliced data if no references
        /// remain. Returns whether self and underlying slice were destroyed or
        /// not: **if the return of this call is true, self now refers to freed
        /// memory and must never be used again**. Further, any references to
        /// self.value.? are likewise invalid.
        pub fn decrement_and_prune_destroy_inner(self: *Self, alloc: Allocator) bool {
            const inner = self.value.?;
            const dead = self.decrement_and_prune(alloc);
            if (dead) alloc.destroy(inner);
            return dead;
        }

        /// Decrement strong count by one and use the given allocator to
        /// destroy both self *and* the underlying sliced data if no references
        /// remain. Returns whether self and underlying slice were destroyed or
        /// not: **if the return of this call is true, self now refers to freed
        /// memory and must never be used again**. Further, any references to
        /// self.value.? are likewise invalid.
        pub fn decrement_and_prune_free_inner(self: *Self, alloc: Allocator) bool {
            const inner = self.value.?;
            const dead = self.decrement_and_prune(alloc);
            if (dead) alloc.free(inner);
            return dead;
        }

        /// Decrement strong count by one and use the given allocator to
        /// destroy self. Then, if no references remain, pass said allocator to
        /// `self.value.deinit(_: std.mem.Allocator)` to defer destruction of
        /// the inner now-garbage to itself. Returns whether self and
        /// underlying data were destroyed or not: **if the return of this call
        /// is true, self now refers to freed memory and must never be used
        /// again**. Further, any references to self.value.? are likewise
        /// invalid.
        pub fn decrement_and_prune_deinit_with_alloc_inner(self: *Self, alloc: Allocator) bool {
            var inner = self.value.?;
            const dead = self.decrement_and_prune(alloc);
            if (dead) inner.deinit(alloc);
            return dead;
        }
    };
}

test "Rc(u8): simple set, increments, decrements, and prune" {
    const SharedStr = Types.HeapedString;
    const hello_world = "Hello World!";
    var str = try testAllocator.alloc(u8, hello_world.len);
    std.mem.copy(u8, str[0..], hello_world);
    var shared_str = try testAllocator.create(SharedStr);
    shared_str.* = SharedStr.init(str);

    try std.testing.expectEqualStrings(hello_world, shared_str.value.?);
    try expect(shared_str.strong_count.load(.Acquire) == 1);
    try shared_str.increment();
    try expect(shared_str.strong_count.load(.Acquire) == 2);
    try expect(!shared_str.decrement_and_prune_free_inner(testAllocator));
    try expect(shared_str.strong_count.load(.Acquire) == 1);

    // This last assertion is testing a lot of things in one swing, but is a
    // realistic usecase: given that we have one remaining reference, decrement
    // *again*, leaving us with no remaining references, and collect garbage by
    // freeing both the underlying u8 slice *and* the Rc itself. Thus, this
    // assertion is only part of the test's succeeding, the rest comes from
    // Zig's GeneralPurposeAllocator not warning us about any leaked memory
    // (which fails the tests at a higher level).
    try expect(shared_str.decrement_and_prune_free_inner(testAllocator));
}
