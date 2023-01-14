// Gale's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

test "gale library test suite" {
    const std = @import("std");
    std.testing.refAllDecls(@This());

    _ = @import("./gale.zig");
    _ = @import("./helpers.zig");
    _ = @import("./internal_error.zig");
    _ = @import("./nucleus_words.zig");
    _ = @import("./object.zig");
    _ = @import("./parsed_word.zig");
    _ = @import("./rc.zig");
    _ = @import("./runtime.zig");
    _ = @import("./stack.zig");
    _ = @import("./types.zig");
    _ = @import("./word.zig");
    _ = @import("./word_list.zig");
    _ = @import("./word_map.zig");
}
