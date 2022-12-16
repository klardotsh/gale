// gluumy: a hackable, type-safe, minimalist, stack-based programming language
//
// (it's pronounced "gloomy" (or maybe "glue me"), and is spelled in lowercase,
// always)
//
//  _.    _  |         ._ _       ._  o  _  |_ _|_   |_   _   _  o ._   _
// (_|   (_| | |_| |_| | | | \/   | | | (_| | | |_   |_) (/_ (_| | | | _>
//        _|                 /           _|                   _|
//
// gluumy's canonical implementation and standard library is released to the
// public domain (or your jurisdiction's closest legal equivalent) under the
// Creative Commons Zero 1.0 dedication, distributed alongside this source in a
// file called COPYING.

const std = @import("std");

const InternalError = @import("./internal_error.zig").InternalError;
const Object = @import("./object.zig").Object;
const ParsedWord = @import("./parsed_word.zig").ParsedWord;
const Rc = @import("./rc.zig").Rc;
const Runtime = @import("./runtime.zig").Runtime;
const Stack = @import("./stack.zig").Stack;
const Word = @import("./word.zig").Word;
const WordList = @import("./word_list.zig").WordList;
const WordMap = @import("./word_map.zig").WordMap;

const nucleus_words = @import("./nucleus_words.zig");

fn heapwrap_impl() void {}

pub fn main() anyerror!void {
    const kernel_words = .{
        .HEAPWRAP = &heapwrap_impl,
    };
    std.debug.print("(Sized: {d} - {any}\n", .{ @sizeOf(@TypeOf(kernel_words)), kernel_words });
}

test {
    std.testing.refAllDecls(@This());

    // Forcibly ref all top-level things per the change introduced in
    // zig-0.10.0. Notablly, union(enum)s don't seem to be "referenced
    // containers", and I'm not sure if that's a bug in my understanding of the
    // new test framework (likely), or in Zig itself (less likely).
    _ = InternalError;
    _ = Object;
    _ = ParsedWord;
    _ = Rc;
    _ = Runtime;
    _ = Stack;
    _ = Word;
    _ = WordList;
    _ = WordMap;

    _ = nucleus_words;
}
