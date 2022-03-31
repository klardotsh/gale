// gluumy: a hackable, type-safe, minimalist, stack-based programming language
//
// (it's pronounced "gloomy" (or maybe "glue me"), and is spelled in lowercase,
// always)
//
//  _.    _  |         ._ _       ._  o  _  |_ _|_   |_   _   _  o ._   _
// (_|   (_| | |_| |_| | | | \/   | | | (_| | | |_   |_) (/_ (_| | | | _>
//        _|                 /           _|                   _|
//
//
// Hi, welcome to the party, my name is klardotsh and I'll be your tour guide
// this evening. Before we begin, let's take a quick moment to make sure your
// editor is in a sane state for reading this:
//
// 1) it needs to be wide enough to see the trailing > at the end of the next line:
// <------------------------------------------------------------------------------------->
//
// look yes I know that's 90 characters but *it's 2022 for zeus's sake*
//
// 2) it needs to be able to handle UTF-8! again, *it's 20-freakin-22*, we
//    standardized this stuff years ago
//
//
// Cool, now let's also make sure your host system, assuming you actually want
// to build this thing (and I hope you do, and I hope you play with it and
// build awesome things with it!), is in order. At time of writing, gluumy
// builds against Zig 0.9, and *only* Zig 0.9. If this code is
// forwards-compatible, great, hopefully I get around to updating this blurb
// some time. Assume this code is not, and will never be, backwards-compatible
// to Zig 0.8 or any previous versions. Aside from the Zig standard library,
// the basic gluumy REPL has no system-level dependencies (though I'm aware
// that, at time of writing, Zig itself requires a full Clang+LLVM stack, and
// thus bootstrapping gluumy on non-standard architectures may be painful).
//
//
// With that said, let's begin the "host" side of gluumy.

const std = @import("std");

// Words in gluumy work somewhat like words in Forth, but with some critically
// important details largely stemming from gluumy's type system, and its
// relatively higher-level nature than Forths that target bare-metal assembly
// (though there's theoretically nothing stopping someone from implementing an
// ASM code generator for gluumy...). Without assuming knowledge of Forth,
// however: a word is a series of UTF-8 characters (excluding 0x20 (space),
// 0x09 (tab), and 0x0A (newline)) identifying an entry in the words
// dictionary, which itself contains a series of instructions, not terribly
// unlike a function definition in most languages.
//
// TODO: more commentary

// First, let's set up some constants. WORD_BUF_LEN is how big of a buffer
// we're willing to allocate to store words as they're input (be that by
// keyboard or by source file: we'll see how that works later). We have to draw
// a line _somewhere_, and since 1KB of RAM is beyond feasible to allocate on
// most systems I'd foresee writing gluumy for, that's the max word length
// until I'm convinced otherwise. This should be safe to change and the
// implementation will scale proportionally.
const WORD_BUF_LEN = 1024;

const ObjType = struct {};

const Word = union(enum) {
    Native: struct {
        flags: packed struct {
            immediate: bool,
            hidden: bool,
        },
    },

    comptime {
        std.testing.refAllDecls(@This());
    }
};

const ObjectHeader = struct {
    obj_type: ObjType,

    comptime {
        std.testing.refAllDecls(@This());
    }
};

const Object = struct {
    header: ObjectHeader,

    comptime {
        std.testing.refAllDecls(@This());
    }
};

const Stack = std.linked_list.TailQueue(Object);

const InterpState = enum(u8) {
    IMMEDIATE = 0,
    COMPILE = 1,
};

pub fn main() anyerror!u8 {
    const stdin = std.io.getStdIn();
    const stdin_reader = stdin.reader();
    const stdout = std.io.getStdOut();
    const stdout_writer = stdout.writer();

    var word_buf: [WORD_BUF_LEN]u8 = undefined;
    var word_len: usize = 0;

    while (true) {
        const word_byte = stdin_reader.readByte() catch |err| switch (err) {
            error.EndOfStream => {
                if (word_len > 0) {
                    try stdout_writer.writeAll("word found eof: ");
                    try stdout_writer.writeAll(word_buf[0..word_len]);
                    try stdout_writer.writeByte('\n');
                }

                break;
            },
            else => |e| return e,
        };

        word_buf[word_len] = word_byte;
        word_len += 1;

        switch (word_byte) {
            ' ', '\t', '\n' => {
                try stdout_writer.writeAll("word found: ");
                try stdout_writer.writeAll(word_buf[0..word_len]);
                try stdout_writer.writeByte('\n');
                word_len = 0;
                continue;
            },
            else => continue,
        }
    }

    return 0;
}

comptime {
    std.testing.refAllDecls(@This());
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
