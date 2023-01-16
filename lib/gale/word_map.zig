// Gale's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

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
