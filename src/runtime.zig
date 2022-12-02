// gluumy's canonical implementation and standard library is released to the
// public domain (or your jurisdiction's closest legal equivalent) under the
// Creative Commons Zero 1.0 dedication, distributed alongside this source in a
// file called COPYING.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Stack = @import("./stack.zig").Stack;

pub const Runtime = struct {
    /// These characters separate identifiers, and can broadly be defined as
    /// "typical ASCII whitespace": UTF-8 codepoints 0x20 (space), 0x09 (tab),
    /// and 0x0A (newline). This technically leaves the door open to
    /// tricky-to-debug behaviors like using 0xA0 (non-breaking space) as
    /// identifiers. With great power comes great responsibility. Don't be
    /// silly.
    const WORD_SPLITTING_CHARS: [3]u8 = .{ ' ', '\t', '\n' };

    /// Speaking of Words: WORD_BUF_LEN is how big of a buffer we're willing to
    /// allocate to store words as they're input. We have to draw a line
    /// _somewhere_, and since 1KB of RAM is beyond feasible to allocate on
    /// most systems I'd foresee writing gluumy for, that's the max word length
    /// until I'm convinced otherwise. This should be safe to change and the
    /// implementation will scale proportionally.
    //
    // TODO: configurable in build.zig
    const WORD_BUF_LEN = 1024;

    const Self = @This();

    alloc: *Allocator,
    private_space: struct {
        interpreter_mode: u8,
    },
    stack: Stack,

    pub fn init(alloc: *Allocator) Self {
        return .{
            .stack = Stack{},
            ._alloc = alloc,
        };
    }
};
