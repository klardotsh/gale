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

const Types = @import("./types.zig");
const WordList = @import("./word_list.zig").WordList;

const SymbolContext = struct {
    const Self = @This();

    pub fn hash(_: Self, s: *Types.HeapedSymbol) u64 {
        return std.hash_map.hashString(s.value.?);
    }
    pub fn eql(_: Self, a: *Types.HeapedSymbol, b: *Types.HeapedSymbol) bool {
        return std.hash_map.eqlString(a.value.?, b.value.?);
    }
};

// TODO: Docs.
pub const WordMap = std.HashMap(*Types.HeapedSymbol, WordList, SymbolContext, std.hash_map.default_max_load_percentage);

test {
    std.testing.refAllDecls(@This());
}
