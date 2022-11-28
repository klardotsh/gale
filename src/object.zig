// gluumy's canonical implementation and standard library is released to the
// public domain (or your jurisdiction's closest legal equivalent) under the
// Creative Commons Zero 1.0 dedication, distributed alongside this source in a
// file called COPYING.

const Rc = @import("./rc.zig").Rc;
const Word = @import("./word.zig").Word;

/// Within our Stack we can store a few primitive types:
pub const Object = union(enum) {
    Boolean: bool,
    UnsignedInt: usize,
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
