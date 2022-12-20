// gluumy's canonical implementation and standard library is released to the
// public domain (or your jurisdiction's closest legal equivalent) under the
// Creative Commons Zero 1.0 dedication, distributed alongside this source in a
// file called COPYING.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testAllocator: Allocator = std.testing.allocator;
const expectEqual = std.testing.expectEqual;

const InternalError = @import("./internal_error.zig").InternalError;
const Stack = @import("./stack.zig").Stack;

pub const Runtime = struct {
    const Self = @This();

    const InterpreterMode = enum(u8) {
        Exec = 0,
        Symbol = 1,
        Ref = 2,
    };

    const PrivateSpace = struct {
        interpreter_mode: InterpreterMode,

        pub fn init() PrivateSpace {
            return PrivateSpace{
                .interpreter_mode = InterpreterMode.Exec,
            };
        }
    };

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

    alloc: Allocator,
    private_space: PrivateSpace,
    stack: *Stack,

    pub fn init(alloc: Allocator) !Self {
        return .{
            .alloc = alloc,
            .stack = try Stack.init(alloc, null),
            .private_space = PrivateSpace.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit();
    }

    pub fn priv_space_set_byte(self: *Self, member: u8, value: u8) InternalError!void {
        return switch (member) {
            0 => self.private_space.interpreter_mode = @intToEnum(InterpreterMode, value),
            else => InternalError.ValueError,
        };
    }

    test "priv_space_set_byte" {
        var rt = try Self.init(testAllocator);
        defer rt.deinit();
        try expectEqual(@as(u8, 0), @enumToInt(rt.private_space.interpreter_mode));
        try rt.priv_space_set_byte(0, 1);
        try expectEqual(@as(u8, 1), @enumToInt(rt.private_space.interpreter_mode));
    }
};

test {
    std.testing.refAllDecls(@This());
}
