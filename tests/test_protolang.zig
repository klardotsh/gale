// Gale's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

const std = @import("std");

test {
    std.testing.refAllDecls(@This());
}
