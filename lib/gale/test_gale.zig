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
    _ = @import("./shape.zig");
    _ = @import("./stack.zig");
    _ = @import("./types.zig");
    _ = @import("./word.zig");
    _ = @import("./word_list.zig");
    _ = @import("./word_map.zig");
    _ = @import("./word_signature.zig");

    // TODO: is this file actually needed?
    _ = @import("./type_system_tests.zig");
}
