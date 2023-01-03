// gluumy's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

const std = @import("std");

const Rc = @import("./rc.zig").Rc;
const Word = @import("./word.zig").Word;

test {
    std.testing.refAllDecls(@This());
}

pub const HeapedOpaque = Rc([]u8);
pub const HeapedString = Rc([]u8);
pub const HeapedSymbol = Rc([]u8);
pub const HeapedWord = Rc(Word);

pub const GluumyOpaque = *HeapedOpaque;
pub const GluumyString = *HeapedString;
pub const GluumySymbol = *HeapedSymbol;
pub const GluumyWord = *HeapedWord;
