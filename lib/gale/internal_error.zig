// Gale's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

const std = @import("std");

pub const InternalError = error{
    AttemptedDestructionOfPopulousRc,
    AttemptedResurrectionOfExhaustedRc, // me too, buddy
    EmptyWord,
    InvalidWordName,
    TypeError,
    Unimplemented,
    UnknownSlashedSuffix,
    ValueError, // TODO: rename???
};

test {
    std.testing.refAllDecls(@This());
}
