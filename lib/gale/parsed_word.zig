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
const expectApproxEqAbs = std.testing.expectApproxEqAbs;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

const InternalError = @import("./internal_error.zig").InternalError;
const helpers = @import("./helpers.zig");

/// Commas can be placed before and/or after simple word lookups to modify the
/// behavior of the stack. These convenience modifiers serve to alleviate
/// common sources of stack shuffling pain in other stack-based languages.
///
/// - Commas before the word indicate that the top object of the stack should be
///   stashed (popped off) during lookup and execution of this word, and
///   restored underneath the effects of the word (unless a trailing comma is
///   additionally used, see below).
///
///   Given `: say-hello ( String -> String )` which returns "Hello, {name}",
///   using the top object off the stack (which must be a String) to fill
///   `name`, and given a Stack with two elements, "World" on top of "Josh",
///   `,say-hello` would result in a stack with "Hello, Josh" on top of "World".
///
/// - Commas after the word indicate that the object on top of the stack prior to
///   execution of the word should be moved to the top of the stack after
///   execution (regardless of how many objects the word places on the stack).
///   This can only be used with purely additive words (those using `<-` stack
///   signatures) unless combined with a leading comma, as its use with words
///   free to consume stack objects would be some combination of ambiguous,
///   confusing, and inelegant.
///
///   Given the Prelude's `Equatable/eq` word, which adds a Boolean to the stack
///   reflecting the equality of the top two objects on the stack, and given a
///   stack with "foo" on top of "bar", `Equatable/eq,` would result in a stack
///   with "foo" on top of `Boolean.False` on top of "bar", functionally
///   equivalent to having run `Equatable/eq swap`, though the stack-juggling
///   sanity restored by this operator scales with the number of objects a word
///   gives.
///
/// - The use of both comma operators on the same word stashes whatever is on
///   top of the stack, looks up and runs the word in question, and restores
///   that object to the top of the stack after the word has completed. There
///   is no restriction of the word being purely-additive as with the
///   trailing-comma-only case above.
///
///   Given the same `say-hello` word as in the leading comma example, and given
///   the same two Strings on the stack, `,say-hello,` would result in a stack
///   with "World" on top of "Hello, Josh".
///
///   Given the same `Equatable/eq` situation as in the trailing comma example,
///   and given the same two Strings on the stack, `,Equatable/eq` would
///   underflow, as only one object would be visible on the stack. Presuming
///   the stack were instead "foo" on top of "bar" on top of "baz",
///   `,Equatable/eq,` would result in `Boolean.False` being inserted between
///   "foo" and "bar".
///
/// Commas are forbidden from use anywhere in word names to reduce confusion
/// (given that `,,,some,thing,,` would be the stashing and hoisting form of
/// `,,some,thing,`, which is comically difficult to make sense of while
/// skimming source code).
///
/// Use of leading and/or trailing commas on any word with an empty stack
/// always results in an underflow, and should be forbidden by analysis tools.
// TODO: ^ should be moved to proper language docs somewhere, as it's only
// somewhat related to `CHAR_COMMA` and those docs are actually good. Nobody
// will ever find them buried deep in a string parser here.
const CHAR_COMMA = helpers.CHAR_COMMA;

const CHAR_DOT = helpers.CHAR_DOT;
const EMPTY_STRING = helpers.EMPTY_STRING;

/// While some FORTHs choose to use s" "s as immediate mode words and then
/// slurp up the character stream in between to use as the body of the string,
/// and while that would certainly be an *easier* and more *consistent* thing
/// to do in the language spec, it's ugly and a horrible user experience, so
/// instead, " (UTF-8 0x22) is one of the few reserved characters for use
const STRING_WORD_DELIMITER = helpers.CHAR_QUOTE_DBL;

/// Borrowing an idea from Ruby, Elixir, and others, identifiers starting with
/// a single colon (:) are reserved for denoting raw identifiers, generally
/// used for defining names of low-level things (say, Shapes and their
/// members).
const SYMBOL_WORD_DELIMITER = helpers.CHAR_COLON;

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
    const Self = @This();

    pub const SimpleWordReference = struct {
        name: []const u8,
        semantics: packed struct {
            stash_before_lookup: bool,
            hoist_after_result: bool,
        },
    };

    String: []const u8,
    Symbol: []const u8,
    Ref: []const u8,
    NumFloat: f64,
    SignedInt: isize,
    UnsignedInt: usize,
    Simple: SimpleWordReference,

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
    pub fn from_input(input: []const u8) !Self {
        if (input.len == 0 or std.mem.eql(u8, EMPTY_STRING, input)) {
            return InternalError.EmptyWord;
        }

        // TODO: This presumes that string quote handling actually happens a
        // level above (read: that the word splitter understands that "these
        // are all one word"), which probably isn't the cleanest design
        if ((input[0] == STRING_WORD_DELIMITER) and
            (input[input.len - 1] == STRING_WORD_DELIMITER))
        {
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

        if (input.len > 1 and input[input.len - 2] == '/') {
            const unsuffixed = input[0 .. input.len - 2];
            switch (input[input.len - 1]) {
                'u' => if (std.fmt.parseInt(usize, unsuffixed, 10) catch null) |parsed| {
                    return ParsedWord{ .UnsignedInt = parsed };
                },
                'i' => if (parseInputAsSignedInt(unsuffixed)) |parsed| {
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

        if (input.len == 1 and input[0] == CHAR_COMMA) {
            return InternalError.InvalidWordName;
        }

        const leading_comma = input[0] == CHAR_COMMA;
        const trailing_comma = input[input.len - 1] == CHAR_COMMA;

        if ((input.len == 1 and leading_comma) or
            (input.len == 2 and leading_comma and trailing_comma))
        {
            return InternalError.InvalidWordName;
        }

        const name_slice_start: usize = if (leading_comma) 1 else 0;
        const name_slice_end: usize = if (trailing_comma) input.len - 1 else input.len;
        const name_slice = input[name_slice_start..name_slice_end];

        for (name_slice) |chr| if (chr == CHAR_COMMA) return InternalError.InvalidWordName;

        return ParsedWord{ .Simple = .{
            .semantics = .{
                .stash_before_lookup = leading_comma,
                .hoist_after_result = trailing_comma,
            },
            .name = name_slice,
        } };
    }

    fn parseInputAsSignedInt(input: []const u8) ?ParsedWord {
        if (std.fmt.parseInt(isize, input, 10) catch null) |parsed| {
            return ParsedWord{ .SignedInt = parsed };
        }

        return null;
    }

    test "errors on empty words" {
        try expectError(InternalError.EmptyWord, from_input(EMPTY_STRING));
    }

    test "parses strings: basic" {
        const result = (try from_input(
            "\"I don't know me and you don't know you\"",
        )).String;

        try expectEqualStrings(
            "I don't know me and you don't know you",
            result,
        );
    }

    test "parses strings: unicodey" {
        const result = (try from_input("\"yeee 🐸☕ hawwww\"")).String;
        try expectEqualStrings("yeee 🐸☕ hawwww", result);
    }

    test "parses symbols: basic" {
        const result = (try from_input(":Testable")).Symbol;
        try expectEqualStrings("Testable", result);
    }

    test "parses symbols: unicodey" {
        const result = (try from_input(":🐸☕")).Symbol;
        try expectEqualStrings("🐸☕", result);
    }

    test "parses refs: basic" {
        const result = (try from_input("&Testable")).Ref;
        try expectEqualStrings("Testable", result);
    }

    test "parses floats: bare" {
        try expectApproxEqAbs(
            @as(f64, 3.14),
            (try from_input("3.14")).NumFloat,
            @as(f64, 0.001),
        );
        try expectApproxEqAbs(
            @as(f64, 0.0),
            (try from_input("0.0")).NumFloat,
            @as(f64, 0.0000001),
        );
        try expectApproxEqAbs(
            @as(f64, 0.0),
            (try from_input("0.000000000000000")).NumFloat,
            @as(f64, 0.0000001),
        );
    }

    test "parses ints: bare" {
        try expectEqual(@as(isize, 420), (try from_input("420")).SignedInt);
        try expectEqual(@as(isize, -1337), (try from_input("-1337")).SignedInt);
    }

    test "parses ints: suffixes" {
        try expectEqual(@as(isize, 420), (try from_input("420/i")).SignedInt);
        try expectEqual(@as(usize, 420), (try from_input("420/u")).UnsignedInt);
    }

    test "parses ints: unhandled suffixes" {
        try expectError(InternalError.UnknownSlashedSuffix, from_input("12345/z"));
    }

    test "parses simple word incantations" {
        const result = (try from_input("@BEFORE_WORD")).Simple;
        try expectEqualStrings("@BEFORE_WORD", result.name);
        try expect(result.semantics.stash_before_lookup == false);
        try expect(result.semantics.hoist_after_result == false);
    }

    test "parses word names: stashing mode" {
        const result = (try from_input(",@BEFORE_WORD")).Simple;
        try expectEqualStrings("@BEFORE_WORD", result.name);
        try expect(result.semantics.stash_before_lookup);
        try expect(result.semantics.hoist_after_result == false);
    }

    test "parses word names: hoisting mode" {
        const result = (try from_input("@BEFORE_WORD,")).Simple;
        try expectEqualStrings("@BEFORE_WORD", result.name);
        try expect(result.semantics.stash_before_lookup == false);
        try expect(result.semantics.hoist_after_result);
    }

    test "parses word names: stashing+hoisting mode" {
        const result = (try from_input(",@BEFORE_WORD,")).Simple;
        try expectEqualStrings("@BEFORE_WORD", result.name);
        try expect(result.semantics.stash_before_lookup);
        try expect(result.semantics.hoist_after_result);
    }

    test "word names must not contain internal commas" {
        try expectError(InternalError.InvalidWordName, from_input(","));
        try expectError(InternalError.InvalidWordName, from_input(",,"));
        try expectError(InternalError.InvalidWordName, from_input(",,,"));
        try expectError(InternalError.InvalidWordName, from_input("foo,bar"));
        try expectError(InternalError.InvalidWordName, from_input(",,foo"));
        try expectError(InternalError.InvalidWordName, from_input(",,foo,"));
        try expectError(InternalError.InvalidWordName, from_input(",,foo,,"));
        try expectError(InternalError.InvalidWordName, from_input(",foo,,"));
        try expectError(InternalError.InvalidWordName, from_input("foo,,"));
    }
};

test {
    std.testing.refAllDecls(@This());
}
