// gluumy's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

pub const InternalError = error{
    AttemptedDestructionOfPopulousRc,
    AttemptedResurrectionOfExhaustedRc, // me too, buddy
    EmptyWord,
    TypeError,
    Unimplemented,
    UnknownSlashedSuffix,
    ValueError, // TODO: rename???
};
