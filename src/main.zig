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
// public domain (or your jurisdiction's closest legal equivalent) under your
// choice of the Creative Commons Zero 1.0 dedication, or the lighter-hearted
// Guthrie Public License, both of which are distributed alongside copies of
// this source code in the LICENSES directory.

// Welcome to what is at this point approximately the One Billionth draft of
// the gluumy implementation, written in Zig. Unfortunately, at time of
// writing, this means this implementation requires the LLVM toolchain at some
// point, meaning Very Beefy Machines are required (either by you, or by a
// packager somewhere) to get gluumy off the ground. However, Zig is working on
// a C codegen backend for their self-hosted compiler, so eventually this
// should be bootstrappable by way of some primitive compiler (perhaps see
// Guix's efforts in this space) -> tcc -> zig -> gluumy. Sorry for that, for
// now, but the future is brighter!
//
// This implementation is heavily commented, in part to allow it to be studied,
// and in part because I am not, by trade or generally, a systems engineer, and
// I'll need references for my future self to be able to maintain this thing,
// and in part because dangit, Jones Forth did a cool thing reading like prose
// that just so happened to also execute: let's do that here, too.

// First of all, we'll be making heavy use of the Zig standard library here.
// It's well-written, well-commented, and most importantly: always available
// wherever a Zig compiler is.
const std = @import("std");

/// Internal errors in the Kernel are codified here, and can be packed
/// alongside a message string in a tuple to provide extra context when
/// appropriate. This is somewhat of a Zig workaround for the
/// core::result::Result.Err(String) construct in Rust, since Zig errors
/// can't carry context with them.
const InternalError = union(enum) {
    Simple: _InternalError,
    Verbose: struct { @"0": _InternalError, @"1": String },
};
const _InternalError = error{
    Unknown,
};

/// Let's also define what a String is internally: a series of 8-bit
/// characters. The language _actually_ expects all strings to be valid UTF-8
/// because it's 20-freakin-22 (at time of writing), but our type here is (for
/// now) looser, and will allow anything. It's likely this type will tighten
/// down later, since userspace will validate that strings are valid (and for
/// all other purposes, such as windows-1251 encoding or some such, there's
/// always userspace shapes stored in Deques with converter functions!)
const String = []u8;

/// The core storage primitive in gluumy is in layman's terms able to be thought
/// of as a loaf of bread, moreso than a stack of plates as we tend to
/// visualize languages like FORTH. A loaf of sliced bread (imagine the sugary,
/// bleached crap that comes in plastic bags here in the States moreso than
/// anything actually edible) is easy and clean to access from either end: I
/// can choose to eat from the left side, the right side, or alternate between
/// the two sides equally easily. Where I'll run into some messy, fragmented
/// problems is if I want the slices somewhere in the middle. Thankfully,
/// I most often want to eat bread from the ends, because I'm not a monster.
/// However, because being a monster is sometimes required in life, we'll later
/// learn about the various ways of accessing the innards of this loaf. For now,
/// just know that we have a doubly-linked list with pointers to the front and
/// back, and that this structure is the sole collection type in gluumy, from
/// which all other collections must be built.
const Deque = std.TailQueue(Object);

/// Within our Deque we can store a few primitive types:
const Object = union(enum) {
    /// The Boolean is unboxed, and simply defers to Zig's bool type.
    Boolean: bool,
    /// The UnsignedInt is likewise an unboxed value, an unsigned integer that
    /// is the pointer size of the target platform.
    UnsignedInt: usize,
    /// The SignedInt is an unboxed value, a signed integer that is the pointer
    /// size of the target platform.
    SignedInt: isize,
    /// Strings are just the slice type we defined above, with all the same
    /// footgun notes, but wrapped into a RefCounter to allow `dup` et. al. to
    /// create new objects that refer to the same underlying memory.
    String: Rc(String),
    /// Symbols are just special flavors of Strings from above.
    Symbol: Rc(String),
    /// Recall that we have exactly one collection type, the Deque. While there
    /// is of course a root Deque, userspace can make as many sub-deques as
    /// they'd like, at unlimited depths. Unlike Strings, these are *not*
    /// RefCounted, because Deques are mutable and trying to reuse mutable
    /// memory is a recipe for pain and suffering.
    Deque: Deque,
    /// We'll learn more about the Shape later, but they are first-class
    /// objects all the same as anything else and can be referenced and
    /// manipulated as such.
    Shape: Rc(Shape),
    /// We'll also learn more about Words later, but these are fairly analogous
    /// to functions or commands in other languages. These are "first-class" in
    /// the sense that they can be passed around after being pulled by
    /// Reference, but are immutable and can only be shadowed by other
    /// immutable Word implementations.
    Word: Rc(Word),
    /// Lastly, Modes are a concept that will be familiar to users of editors
    /// like Vim, Kakoune, or Helix: they toggle the vocabulary of Words
    /// available in a given execution context. We'll learn plenty about these
    /// later.
    Mode: Rc(Mode),
};

/// Several of the above referred to an Rc type, which is a concept lifted
/// straight from Rust. For now, only strong references are supported.
fn Rc(comptime T: type) type {
    return struct {
        strong_count: *usize,
        value: *T,

        fn clone(self: *Rc) Rc {
            self.strong_count.* += 1;

            return Rc{
                .strong_count = self.strong_count,
                .value = self.value,
            };
        }

        fn deinit(self: *Rc) !InternalError {
            if (self.strong_count.* == 0) {
                unreachable;
            }
        }
    };
}

/// gluumy's type system is actually pretty dumb and/or simple, depending on
/// how you'd like to look at it, in that it is purely structural. It's also
/// a touch complex, in that the same object may fit a Shape in one Mode, but
/// not in another. Thus, our representation of a Shape is somewhat of a
/// "strong duck typing", and is appropriately abstract.
//
// This duck doesn't skip leg day.
const Shape = union(enum) {
    // There's no real reason to leave this up to platform choice, but since
    // the overall union will be padded to its maximum member size anyway,
    // and Concrete is (relatively) huge, we may as well allow as many
    // generics as fit here.
    Generic: usize,

    Concrete: struct {
        derives: std.TailQueue(*Shape.Concrete),
        responds_to: std.StringArrayHashMap(std.SinglyLinkedList(Signature)),
    },
    
    comptime {
        std.testing.refAllDecls(@This());
    }
};

const Signature = struct {
    takes: ?[]*Shape,
    gives: ?[]*Shape,
};

const Word = struct {
    implementation: union(enum) {
        Native: fn(Deque) Deque,
        Sequence: []*Word,
    },
    signature: *Signature,
    
    comptime {
        std.testing.refAllDecls(@This());
    }
};

/// Words within Modes are stored by their string identifiers first and
/// foremost, as that's the most frequent lookup.
const WordTable = std.StringArrayHashMap(WordTableInner);

/// Next level in the stacking doll is to disambiguate words within a Mode by
/// whatever the first thing they pop off the stack is, if anything. This is
/// again a bit of an optimization: at runtime, we will always know what the
/// top thing on the Deque is if it exists, so disambiguation can be made
/// quick.
const WordTableInner = std.AutoHashMap(?Shape, WordList);

/// Finally, we'll have to brute-force our way through a (now heavily narrowed)
/// list of Word definitions to find the best fitting candidate.
const WordList = std.SinglyLinkedList(Word);

const Mode = union(enum) {
    Single: struct {
        name: String,
        table: *WordTable,
    },
    Multi: []Rc(Mode),
    
    comptime {
        std.testing.refAllDecls(@This());
    }
};

const Runtime = struct {
    current_mode: Rc(Mode),
    all_modes: std.StringArrayHashMap(Rc(Mode)),
    root_deque: Deque,
    
    comptime {
        std.testing.refAllDecls(@This());
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

/// While some FORTHs choose to use s" "s as immediate mode words and then
/// slurp up the character stream in between to use as the body of the string,
/// and while that would certainly be an *easier* and more *consistent* thing
/// to do in the language spec, it's ugly and a horrible user experience, so
/// instead, " (UTF-8 0x22) is one of the few reserved characters for use
const STRING_WORD_DELIMITER = '"';

/// Borrowing an idea from Ruby, Elixir, and others, identifiers starting with
/// a single quote are reserved for denoting raw identifiers, generally used
/// for defining names of low-level things (say, Shapes and their members).
const SYMBOL_WORD_DELIMITER = '\'';

/// Finally, borrowing an idea from countless languages, identifiers starting
/// with ampersands are also reserved: the & will be dropped, and the
/// remaining characters will be used as the name of the thing to look up
/// following the exact same rules as we'd normally use for execution flow
/// (meaning we'll search only relevant Modes and will disambiguate based on
/// the current Deque Signature - more on that later), but rather than calling
/// the Word, we'll return a Reference to it.
///
/// Referencing a primitive type, for example with '1, is redundant, and will
/// still place the primitive type onto the Deque.
const REF_WORD_DELIMITER = '&';

/// Speaking of Words: WORD_BUF_LEN is how big of a buffer we're willing to
/// allocate to store words as they're input. We have to draw a line
/// _somewhere_, and since 1KB of RAM is beyond feasible to allocate on most
/// systems I'd foresee writing gluumy for, that's the max word length until
/// I'm convinced otherwise. This should be safe to change and the
/// implementation will scale proportionally.
const WORD_BUF_LEN = 1024;

/// Pluck common boolean representations from an environment variable `name` as
/// an actual boolean. 1, true, TRUE, yes, and YES are accepted truthy values,
/// anything else is false.
pub fn getenv_boolean(name: []const u8) bool {
    const from_env = std.os.getenv(name) orelse "";
    inline for (.{ "1", "true", "TRUE", "yes", "YES" }) |pattern| {
        if (std.mem.eql(u8, from_env, pattern)) {
            return true;
        }
    }

    return false;
}

pub fn main() anyerror!void {
    std.log.info("All your codebase are belong to us.", .{});
}

test "reference everything" {
    std.testing.refAllDecls(@This());
}
