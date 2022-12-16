// gluumy's canonical implementation and standard library is released to the
// public domain (or your jurisdiction's closest legal equivalent) under the
// Creative Commons Zero 1.0 dedication, distributed alongside this source in a
// file called COPYING.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testAllocator: Allocator = std.testing.allocator;
const expect = std.testing.expect;

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
            if (self.value == null) {
                return error.CannotResurrectAfterExhausted;
            }

            _ = self.strong_count.fetchAdd(1, .Monotonic);
        }

        /// Returned boolean reflects the livelihood of the object after this
        /// decrement: if false, it is assumed to be safe for callers to free
        /// the underlying data.
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
    };
}

test "Rc(u8): simple set, increments, decrements" {
    const SharedStr = Rc([]u8);

    const hello_world = "Hello World!";
    // Imagine, if you will, this string is in some interning dictionary
    // somewhere, or whatever. This is the raw memory our Rc will wrap a
    // lifecycle for.
    var str = try testAllocator.alloc(u8, hello_world.len);
    defer testAllocator.free(str);
    std.mem.copy(u8, str[0..], hello_world);

    var shared_str = SharedStr.init(str);

    try std.testing.expectEqualStrings(hello_world, shared_str.value.?);
    try expect(shared_str.strong_count.load(.Acquire) == 1);
    try shared_str.increment();
    try expect(shared_str.strong_count.load(.Acquire) == 2);
    try expect(shared_str.decrement());
    try expect(!shared_str.decrement());
    try expect(shared_str.strong_count.load(.Acquire) == 0);
    try expect(shared_str.value == null);
}
