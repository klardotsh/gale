// gluumy's canonical implementation and standard library is released to the
// public domain (or your jurisdiction's closest legal equivalent) under the
// Creative Commons Zero 1.0 dedication, distributed alongside this source in a
// file called COPYING.

const std = @import("std");

const Types = @import("./types.zig");
const WordList = @import("./word_list.zig").WordList;

const GluumySymbolContext = struct {
    const Self = @This();

    pub fn hash(_: Self, s: Types.GluumySymbol) u64 {
        return std.hash_map.hashString(s.value.?);
    }
    pub fn eql(_: Self, a: Types.GluumySymbol, b: Types.GluumySymbol) bool {
        return std.hash_map.eqlString(a.value.?, b.value.?);
    }
};

// TODO: Docs.
pub const WordMap = std.HashMap(Types.GluumySymbol, WordList, GluumySymbolContext, std.hash_map.default_max_load_percentage);
