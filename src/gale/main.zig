// Gale's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

const std = @import("std");
const gale = @import("gale");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const runtime = try gale.Runtime.init(gpa.allocator());
    std.debug.print("{any}\n", .{runtime});
}
