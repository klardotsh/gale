// Gale's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

const std = @import("std");

const Object = @import("./object.zig").Object;
const Rc = @import("./rc.zig").Rc;
const Stack = @import("./stack.zig").Stack;
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

pub const PopSingle = struct {
    item: Object,
    now_top_stack: *Stack,
};

pub const PeekPair = struct {
    near: *Object,
    far: ?*Object,
};

pub const PopPair = struct {
    near: Object,
    far: Object,
    now_top_stack: *Stack,
};

pub const PopPairExternal = struct {
    near: Object,
    far: Object,
};

pub const PeekTrio = struct {
    near: *Object,
    far: ?*Object,
    farther: ?*Object,
};

pub const PopTrio = struct {
    near: Object,
    far: Object,
    farther: Object,
    now_top_stack: *Stack,
};

pub const PopTrioExternal = struct {
    near: Object,
    far: Object,
    farther: Object,
};
