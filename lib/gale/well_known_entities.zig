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

const Runtime = @import("./runtime.zig").Runtime;
const Shape = @import("./shape.zig").Shape;
const WordSignature = @import("./word_signature.zig").WordSignature;

// TODO: Should these be pointers to a Shape pool much like the signature
// situation below?
pub const WellKnownShapeStorage = [std.meta.fields(WellKnownShape).len]Shape;
pub const WellKnownSignatureStorage = [std.meta.fields(WellKnownSignature).len]*WordSignature;

/// A well-known Shape ships as part of the Runtime because it reflects a
/// language primitive, rather than anything created in userspace.
pub const WellKnownShape = enum(u8) {
    UnboundedBoolean = 0,
    UnboundedString,
    UnboundedSymbol,
    UnboundedUnsignedInt,
    UnboundedSignedInt,
    UnboundedFloat,
    UnboundedWord,
    UnboundedWordSignature,
};

pub const WellKnownSignature = enum(u8) {
    NullarySingleUnboundedBoolean = 0,
    NullarySingleUnboundedString,
    NullarySingleUnboundedSymbol,
    NullarySingleUnboundedUnsignedInt,
    NullarySingleUnboundedSignedInt,
    NullarySingleUnboundedFloat,
    NullarySingleUnboundedWord,
    NullarySingleUnboundedWordSignature,
};

pub fn shape_storage() WellKnownShapeStorage {
    return .{
        // This explicit cast avoids an error at array fill time:
        // error: expected type '@TypeOf(undefined)', found 'shape.Shape'
        @as(Shape, undefined),
    } ** @typeInfo(WellKnownShapeStorage).Array.len;
}

pub fn signature_storage() WellKnownSignatureStorage {
    return .{
        // This explicit cast avoids an error at array fill time:
        // error: expected type '@TypeOf(undefined)', found 'shape.Shape'
        @as(*WordSignature, undefined),
    } ** @typeInfo(WellKnownSignatureStorage).Array.len;
}

pub fn populate(rt: *Runtime) !void {
    for (rt.well_known_shapes) |*it, idx| {
        switch (@intToEnum(WellKnownShape, idx)) {
            .UnboundedBoolean => {
                it.* = Shape.new_containing_primitive(.Unbounded, .Boolean);
                var stored = try rt.signatures.getOrPut(WordSignature{ .NullarySingle = it });
                stored.value_ptr.* = {};
                rt.well_known_signatures[@enumToInt(WellKnownSignature.NullarySingleUnboundedBoolean)] =
                    stored.key_ptr;
            },
            .UnboundedString => {
                it.* = Shape.new_containing_primitive(.Unbounded, .CharSlice);
                var stored = try rt.signatures.getOrPut(WordSignature{ .NullarySingle = it });
                stored.value_ptr.* = {};
                rt.well_known_signatures[@enumToInt(WellKnownSignature.NullarySingleUnboundedString)] =
                    stored.key_ptr;
            },
            .UnboundedSymbol => {
                it.* = Shape.new_containing_primitive(.Unbounded, .CharSlice);
                var stored = try rt.signatures.getOrPut(WordSignature{ .NullarySingle = it });
                stored.value_ptr.* = {};
                rt.well_known_signatures[@enumToInt(WellKnownSignature.NullarySingleUnboundedSymbol)] =
                    stored.key_ptr;
            },
            .UnboundedUnsignedInt => {
                it.* = Shape.new_containing_primitive(.Unbounded, .UnsignedInt);
                var stored = try rt.signatures.getOrPut(WordSignature{ .NullarySingle = it });
                stored.value_ptr.* = {};
                rt.well_known_signatures[@enumToInt(WellKnownSignature.NullarySingleUnboundedUnsignedInt)] =
                    stored.key_ptr;
            },
            .UnboundedSignedInt => {
                it.* = Shape.new_containing_primitive(.Unbounded, .SignedInt);
                var stored = try rt.signatures.getOrPut(WordSignature{ .NullarySingle = it });
                stored.value_ptr.* = {};
                rt.well_known_signatures[@enumToInt(WellKnownSignature.NullarySingleUnboundedSignedInt)] =
                    stored.key_ptr;
            },
            .UnboundedFloat => {
                it.* = Shape.new_containing_primitive(.Unbounded, .Float);
                var stored = try rt.signatures.getOrPut(WordSignature{ .NullarySingle = it });
                stored.value_ptr.* = {};
                rt.well_known_signatures[@enumToInt(WellKnownSignature.NullarySingleUnboundedFloat)] =
                    stored.key_ptr;
            },
            .UnboundedWord => {
                it.* = Shape.new_containing_primitive(.Unbounded, .Word);
                var stored = try rt.signatures.getOrPut(WordSignature{ .NullarySingle = it });
                stored.value_ptr.* = {};
                rt.well_known_signatures[@enumToInt(WellKnownSignature.NullarySingleUnboundedWord)] =
                    stored.key_ptr;
            },
            .UnboundedWordSignature => {
                it.* = Shape.new_containing_primitive(.Unbounded, .WordSignature);
                var stored = try rt.signatures.getOrPut(WordSignature{ .NullarySingle = it });
                stored.value_ptr.* = {};
                rt.well_known_signatures[@enumToInt(WellKnownSignature.NullarySingleUnboundedWordSignature)] =
                    stored.key_ptr;
            },
        }
    }
}
