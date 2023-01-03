// gluumy's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testAllocator: Allocator = std.testing.allocator;
const expectEqual = std.testing.expectEqual;

// TODO: this import should later be "libgluumy", see <root>/src/main.lib.zig
// for more commentary
const gluumy = @import("gluumy");
const Runtime = gluumy.Runtime;

test "push primitives" {
    var rt = try Runtime.init(testAllocator);
    defer rt.deinit_guard_for_empty_stack();
}
