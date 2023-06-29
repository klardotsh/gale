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
const expect = std.testing.expect;

// Just silly stuff that's nice to access by name
pub const CHAR_AMPER = '&';
pub const CHAR_COLON = ':';
pub const CHAR_COMMA = ',';
pub const CHAR_DOT = '.';
pub const CHAR_HASH = '#';
pub const CHAR_NEWLINE = '\n';
pub const CHAR_QUOTE_SGL = '\'';
pub const CHAR_QUOTE_DBL = '"';
pub const CHAR_SPACE = ' ';
pub const CHAR_TAB = '\t';
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

test {
    std.testing.refAllDecls(@This());
}
