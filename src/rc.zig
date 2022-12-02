// gluumy's canonical implementation and standard library is released to the
// public domain (or your jurisdiction's closest legal equivalent) under the
// Creative Commons Zero 1.0 dedication, distributed alongside this source in a
// file called COPYING.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testAllocator: Allocator = std.testing.allocator;
const expect = std.testing.expect;

// This implementation is nearly exactly as described in the comments of
// https://github.com/ziglang/zig/blob/02e1facc72fa9cb8e4793ecf114fdd61ea8df6bd/lib/std/atomic/Atomic.zig,
// which means it's probably "quite good enough, and better than Josh would
// write himself". Take it from someone who just referred to himself in the
// third person.
pub fn Rc(comptime T: type) type {
    return struct {
        const Self = @This();
        const RefCount = std.atomic.Atomic(u16);

        allocator: Allocator,
        strong_count: RefCount,
        value: ?[]T,

        fn init(allocator: Allocator, size: usize) !Self {
            return @This(){
                .allocator = allocator,
                .strong_count = RefCount.init(1),
                .value = try allocator.alloc(T, size),
            };
        }

        fn increment(self: *Self) void {
            _ = self.strong_count.fetchAdd(1, .Monotonic);
        }

        fn decrement(self: *Self) void {
            // Release ensures code before unref() happens-before the count is
            // decremented as dropFn could be called by then.
            if (self.strong_count.fetchSub(1, .Release) == 1) {
                // Acquire ensures count decrement and code before previous
                // unrefs()s happens-before we call dropFn below.
                self.strong_count.fence(.Acquire);
                if (self.value) |ptr| {
                    self.allocator.free(ptr);
                    self.value = null;
                }
            }
        }
    };
}

test "Rc(u8): simple set, increments, decrements" {
    const SharedStr = Rc(u8);

    const hello_world = "Hello World!";
    var shared_str = try SharedStr.init(testAllocator, hello_world.len);
    std.mem.copy(u8, shared_str.value.?[0..], hello_world);
    try std.testing.expectEqualStrings(hello_world, shared_str.value.?);
    try expect(shared_str.strong_count.load(.Acquire) == 1);
    shared_str.increment();
    try expect(shared_str.strong_count.load(.Acquire) == 2);
    shared_str.decrement();
    shared_str.decrement();
    try expect(shared_str.strong_count.load(.Acquire) == 0);
    try expect(shared_str.value == null);
}
