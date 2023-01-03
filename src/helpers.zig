// gluumy's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

const std = @import("std");
const expect = std.testing.expect;

// Just silly stuff that's nice to access by name
pub const CHAR_AMPER = '&';
pub const CHAR_DOT = '.';
pub const CHAR_QUOTE_SGL = '\'';
pub const CHAR_QUOTE_DBL = '"';
pub const EMPTY_STRING = "";

pub fn bool_from_human_str(val: []const u8) bool {
    if (std.mem.eql(u8, val, "")) {
        return false;
    }

    inline for (.{ "1", "true", "TRUE", "yes", "YES" }) |pattern| {
        if (std.mem.eql(u8, val, pattern)) {
            return true;
        }
    }

    return false;
}

test "bool_from_human_str" {
    try expect(bool_from_human_str("1"));
    try expect(bool_from_human_str("true"));
    try expect(bool_from_human_str("TRUE"));
    try expect(bool_from_human_str("yes"));
    try expect(bool_from_human_str("YES"));
    try expect(bool_from_human_str("") == false);
    try expect(bool_from_human_str("0") == false);
    try expect(bool_from_human_str("no") == false);
    try expect(bool_from_human_str("2") == false);
    try expect(bool_from_human_str("narp") == false);
}

/// Pluck common boolean representations from an environment variable `name` as
/// an actual boolean. 1, true, TRUE, yes, and YES are accepted truthy values,
/// anything else is false.
pub fn getenv_boolean(name: []const u8) bool {
    return bool_from_human_str(std.os.getenv(name) orelse "");
}
