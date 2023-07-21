// Copyright (C) 2023 Josh Klar aka "klardotsh" <josh@klar.sh>
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
// REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
// FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
// INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
// LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
// OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
// PERFORMANCE OF THIS SOFTWARE.

const std = @import("std");

const Object = @import("./object.zig").Object;
const Rc = @import("./rc.zig").Rc;
const Stack = @import("./stack.zig").Stack;
const Word = @import("./word.zig").Word;

test {
    std.testing.refAllDecls(@This());
}

pub const ObjectArray = std.ArrayList(Object);

pub const HeapedArray = Rc(ObjectArray);
pub const HeapedOpaque = Rc([]u8);
pub const HeapedString = Rc([]u8);
pub const HeapedSymbol = Rc([]u8);
pub const HeapedWord = Rc(Word);

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
