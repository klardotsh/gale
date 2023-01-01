// gluumy's canonical implementation and standard library is released to the
// public domain (or your jurisdiction's closest legal equivalent) under the
// Creative Commons Zero 1.0 dedication, distributed alongside this source in a
// file called COPYING.

pub const InternalError = error{
    AttemptedDestructionOfPopulousRc,
    AttemptedResurrectionOfExhaustedRc, // me too, buddy
    EmptyWord,
    TypeError,
    Unimplemented,
    UnknownSlashedSuffix,
    ValueError, // TODO: rename???
};
