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

// Welcome to what is at this point approximately the One Billionth draft of
// the gluumy implementation, written in Zig. This implementation is heavily
// commented, in part to allow it to be studied, and in part because I am not,
// by trade or generally, a systems engineer, and I'll need references for my
// future self to be able to maintain this thing, and in part because dangit,
// Jones Forth did a cool thing reading like prose that just so happened to
// also execute: let's do that here, too.

// First of all, we'll be making heavy use of the Zig standard library here.
// It's well-written, well-commented, and most importantly: always available
// wherever a Zig compiler is.
const std = @import("std");
const IAllocator = std.mem.Allocator;
const testAllocator: IAllocator = std.testing.allocator;
const expect = std.testing.expect;

const InternalError = @import("./internal_error.zig").InternalError;
const ParsedWord = @import("./parsed_word.zig").ParsedWord;
const Rc = @import("./rc.zig").Rc;
const helpers = @import("./helpers.zig");

/// Let's also define what a String is internally: a series of 8-bit
/// characters. The language _actually_ expects all strings to be valid UTF-8
/// because it's 20-freakin-22 (at time of writing), but our type here is (for
/// now) looser, and will allow anything. It's likely this type will tighten
/// down later, since userspace will validate that strings are valid (and for
/// all other purposes, such as windows-1251 encoding or some such, there's
/// always userspace shapes stored in Opaques with converter functions!)
const String = []const u8;

/// TODO: Docs.
const Stack = std.atomic.Stack(Object);

/// TODO: Docs.
const Word = union(enum) {
    // I can see a world where this should return something other than void to
    // allow for optimizations later...
    Primitive: *fn (*Stack) void,
    Compound: []Word,
};

/// Within our Stack we can store a few primitive types:
const Object = union(enum) {
    /// The Boolean is unboxed, and simply defers to Zig's bool type.
    Boolean: bool,
    /// The UnsignedInt is likewise an unboxed value, an unsigned integer that
    /// is the pointer size of the target platform.
    UnsignedInt: usize,
    /// The SignedInt is an unboxed value, a signed integer that is the pointer
    /// size of the target platform.
    SignedInt: isize,
    String: *Rc(u8),
    Symbol: *Rc(u8),
    /// Opaque represents a blob of memory that is left to userspace to manage
    /// manually. TODO more docs here.
    Opaque: *Rc(usize),
    /// We'll also learn more about Words later, but these are fairly analogous
    /// to functions or commands in other languages. These are "first-class" in
    /// the sense that they can be passed around after being pulled by
    /// Reference, but are immutable and can only be shadowed by other
    /// immutable Word implementations.
    Word: *Rc(Word),
};

const Runtime = struct {
    //private_space:
    stack: Stack,

    _alloc: *IAllocator,

    pub fn init(alloc: *IAllocator) @This() {
        return .{
            .stack = Stack{},
            ._alloc = alloc,
        };
    }
};

// More or less anything is valid as a Word identifier. There's two categories
// of exceptions to this rule, split into three constants.

/// These characters separate identifiers, and can broadly be defined as
/// "typical ASCII whitespace": UTF-8 codepoints 0x20 (space), 0x09 (tab), and
/// 0x0A (newline). This technically leaves the door open to tricky-to-debug
/// behaviors like using 0xA0 (non-breaking space) as identifiers. With great
/// power comes great responsibility. Don't be silly.
const WORD_SPLITTING_CHARS: [3]u8 = .{ ' ', '\t', '\n' };

/// Speaking of Words: WORD_BUF_LEN is how big of a buffer we're willing to
/// allocate to store words as they're input. We have to draw a line
/// _somewhere_, and since 1KB of RAM is beyond feasible to allocate on most
/// systems I'd foresee writing gluumy for, that's the max word length until
/// I'm convinced otherwise. This should be safe to change and the
/// implementation will scale proportionally.
const WORD_BUF_LEN = 1024;

const PrivateSpace = struct {
    interpreter_mode: u8,
};

pub fn main() anyerror!void {
    const private_space = std.mem.zeroInit(PrivateSpace, .{});
    std.debug.print("(Sized: {d} - {any}", .{ @sizeOf(PrivateSpace), private_space });
}

test {
    std.testing.refAllDecls(@This());

    // So far it appears that union(enum)s aren't "referenced containers" as
    // far as the zig-0.10.0 test runner is concerned with refAllDecls(), so
    // for now, manually reference all containers which have tests to ensure
    // those tests are run.
    _ = ParsedWord;

    _ = Rc;
}
