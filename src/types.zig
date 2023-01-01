// gluumy's canonical implementation and standard library is released to the
// public domain (or your jurisdiction's closest legal equivalent) under the
// Creative Commons Zero 1.0 dedication, distributed alongside this source in a
// file called COPYING.

const Rc = @import("./rc.zig").Rc;
const Word = @import("./word.zig").Word;

pub const HeapedOpaque = Rc([]u8);
pub const HeapedString = Rc([]u8);
pub const HeapedSymbol = Rc([]u8);
pub const HeapedWord = Rc(Word);

pub const GluumyOpaque = *HeapedOpaque;
pub const GluumyString = *HeapedString;
pub const GluumySymbol = *HeapedSymbol;
pub const GluumyWord = *HeapedWord;
