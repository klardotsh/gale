// gluumy's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

const std = @import("std");

const InternalError = @import("./internal_error.zig").InternalError;
const helpers = @import("./helpers.zig");

const CHAR_DOT = helpers.CHAR_DOT;
const EMPTY_STRING = helpers.EMPTY_STRING;

/// While some FORTHs choose to use s" "s as immediate mode words and then
/// slurp up the character stream in between to use as the body of the string,
/// and while that would certainly be an *easier* and more *consistent* thing
/// to do in the language spec, it's ugly and a horrible user experience, so
/// instead, " (UTF-8 0x22) is one of the few reserved characters for use
const STRING_WORD_DELIMITER = helpers.CHAR_QUOTE_DBL;

/// Borrowing an idea from Ruby, Elixir, and others, identifiers starting with
/// a single quote are reserved for denoting raw identifiers, generally used
/// for defining names of low-level things (say, Shapes and their members).
const SYMBOL_WORD_DELIMITER = helpers.CHAR_QUOTE_SGL;

/// Finally, borrowing an idea from countless languages, identifiers starting
/// with ampersands are also reserved: the & will be dropped, and the remaining
/// characters will be used as the name of the thing to look up following the
/// exact same rules as we'd normally use for execution flow, but rather than
/// calling the Word, we'll return a Reference to it.
///
/// Referencing a primitive type, for example with '1, is redundant, and will
/// still place the primitive type onto the Stack.
const REF_WORD_DELIMITER = helpers.CHAR_AMPER;

pub const ParsedWord = union(enum) {
    String: []const u8,
    Symbol: []const u8,
    Ref: []const u8,
    NumFloat: f64,
    SignedInt: isize,
    UnsignedInt: usize,
    Simple: []const u8,

    /// In any event of ambiguity, input strings are parsed in the following
    /// order of priority:
    ///
    /// - Empty input (returns EmptyWord error)
    /// - Strings
    /// - Symbols
    /// - Ref strings
    /// - Floats
    /// - Ints
    /// - Assumed actual words ("Simples")
    //
    // TODO: symbols should be interned somewhere for memory savings. How,
    // exactly, to do this, is left as an exercise to my future self.
    pub fn from_input(input: []const u8) !@This() {
        if (input.len == 0 or std.mem.eql(u8, EMPTY_STRING, input)) {
            return InternalError.EmptyWord;
        }

        // TODO: This presumes that string quote handling actually happens a
        // level above (read: that the word splitter understands that "these
        // are all one word"), which probably isn't the cleanest design
        if (input[0] == STRING_WORD_DELIMITER and input[input.len - 1] == STRING_WORD_DELIMITER) {
            return ParsedWord{ .String = input[1 .. input.len - 1] };
        }

        if (input[0] == SYMBOL_WORD_DELIMITER) {
            return ParsedWord{ .Symbol = input[1..input.len] };
        }

        if (input[0] == REF_WORD_DELIMITER) {
            return ParsedWord{ .Ref = input[1..input.len] };
        }

        if (std.mem.indexOfScalar(u8, input, CHAR_DOT) != null) {
            if (std.fmt.parseFloat(f64, input) catch null) |parsed| {
                return ParsedWord{ .NumFloat = parsed };
            }
        }

        if (input[input.len - 2] == '/') {
            switch (input[input.len - 1]) {
                'u' => if (std.fmt.parseInt(usize, input[0 .. input.len - 2], 10) catch null) |parsed| {
                    return ParsedWord{ .UnsignedInt = parsed };
                },
                'i' => if (parseInputAsSignedInt(input[0 .. input.len - 2])) |parsed| {
                    return parsed;
                },
                else => return InternalError.UnknownSlashedSuffix,
            }
        }

        if (std.fmt.parseInt(isize, input, 10) catch null) |parsed| {
            return ParsedWord{ .SignedInt = parsed };
        }

        if (std.fmt.parseInt(usize, input, 10) catch null) |parsed| {
            return ParsedWord{ .UnsignedInt = parsed };
        }

        return ParsedWord{ .Simple = input };
    }

    fn parseInputAsSignedInt(input: []const u8) ?ParsedWord {
        if (std.fmt.parseInt(isize, input, 10) catch null) |parsed| {
            return ParsedWord{ .SignedInt = parsed };
        }

        return null;
    }

    test "errors on empty words" {
        try std.testing.expectError(InternalError.EmptyWord, from_input(EMPTY_STRING));
    }

    test "parses strings: basic" {
        const result = (try from_input(
            "\"I don't know me and you don't know you\"",
        )).String;

        try std.testing.expectEqualStrings(
            "I don't know me and you don't know you",
            result,
        );
    }

    test "parses strings: unicodey" {
        const result = (try from_input(
            "\"yeee 🐸☕ hawwww\"",
        )).String;

        try std.testing.expectEqualStrings(
            "yeee 🐸☕ hawwww",
            result,
        );
    }

    test "parses symbols: basic" {
        const result = (try from_input(
            "'Testable",
        )).Symbol;

        try std.testing.expectEqualStrings(
            "Testable",
            result,
        );
    }

    test "parses symbols: unicodey" {
        const result = (try from_input(
            "'🐸☕",
        )).Symbol;

        try std.testing.expectEqualStrings(
            "🐸☕",
            result,
        );
    }

    test "parses refs: basic" {
        const result = (try from_input(
            "&Testable",
        )).Ref;

        try std.testing.expectEqualStrings(
            "Testable",
            result,
        );
    }

    test "parses floats: bare" {
        try std.testing.expectApproxEqAbs(
            @as(f64, 3.14),
            (try from_input("3.14")).NumFloat,
            @as(f64, 0.001),
        );
        try std.testing.expectApproxEqAbs(
            @as(f64, 0.0),
            (try from_input("0.0")).NumFloat,
            @as(f64, 0.0000001),
        );
        try std.testing.expectApproxEqAbs(
            @as(f64, 0.0),
            (try from_input("0.000000000000000")).NumFloat,
            @as(f64, 0.0000001),
        );
    }

    test "parses ints: bare" {
        try std.testing.expectEqual(
            @as(isize, 420),
            (try from_input("420")).SignedInt,
        );
        try std.testing.expectEqual(
            @as(isize, -1337),
            (try from_input("-1337")).SignedInt,
        );
    }

    test "parses ints: suffixes" {
        try std.testing.expectEqual(
            @as(isize, 420),
            (try from_input("420/i")).SignedInt,
        );

        try std.testing.expectEqual(
            @as(usize, 420),
            (try from_input("420/u")).UnsignedInt,
        );
    }

    test "parses ints: unhandled suffixes" {
        try std.testing.expectError(InternalError.UnknownSlashedSuffix, from_input("12345/z"));
    }

    test "parses simple word incantations" {
        const result = (try from_input(
            "@BEFORE_WORD",
        )).Simple;

        try std.testing.expectEqualStrings(
            "@BEFORE_WORD",
            result,
        );
    }
};

test {
    std.testing.refAllDecls(@This());
}
