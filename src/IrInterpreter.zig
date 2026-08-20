// SPDX-FileCopyrightText: 2026 Iyad
//
// SPDX-License-Identifier: Apache-2.0

//! An interpreter that runs an `Ir`.
//!
//! Semantics match `Interpreter`. The two are kept as independent implementations,
//! so their output can be diffed to validate lowering.

const std = @import("std");
const Io = std.Io;
const testing = std.testing;

const Ir = @import("Ir.zig");

const IrInterpreter = @This();

_tape: [30000]u8,
_pointer: usize,
_reader: *Io.Reader,
_writer: *Io.Writer,

/// An error raised while running a program.
pub const Error = error{
    /// A move took the pointer past the last cell.
    PointerOverflow,

    /// A move took the pointer before the first cell.
    PointerUnderflow,

    /// Reading input failed.
    ReadFailed,

    /// Writing output failed.
    WriteFailed,
};

/// Creates an `IrInterpreter` where `read` takes from `reader` and `write` goes to `writer`.
///
/// Both must outlive the interpreter.
pub fn init(reader: *Io.Reader, writer: *Io.Writer) IrInterpreter {
    return .{
        ._tape = @splat(0),
        ._pointer = 0,
        ._reader = reader,
        ._writer = writer,
    };
}

/// Runs `ir` to completion.
///
/// Output is flushed before returning, including when the program fails.
pub fn run(self: *IrInterpreter, ir: Ir) Error!void {
    defer self._writer.flush() catch {};

    var ip: usize = 0;
    while (ip < ir.instructions.len) {
        switch (ir.instructions[ip]) {
            .move => |n| {
                const target = @as(isize, @intCast(self._pointer)) + n;
                if (target >= self._tape.len) return error.PointerOverflow;
                if (target < 0) return error.PointerUnderflow;
                self._pointer = @intCast(target);
            },
            .add => |n| {
                self._tape[self._pointer] +%= @bitCast(n);
            },
            .read => self._tape[self._pointer] = self._reader.takeByte() catch |err|
                switch (err) {
                    error.EndOfStream => 0,
                    else => return error.ReadFailed,
                },
            .write => self._writer.writeByte(self._tape[self._pointer]) catch return error.WriteFailed,
            .jump_if_zero => |target| if (self._tape[self._pointer] == 0) {
                ip = target;
                continue;
            },
            .jump_if_nonzero => |target| if (self._tape[self._pointer] != 0) {
                ip = target;
                continue;
            },
        }

        ip += 1;
    }
}

fn expectOutput(expected: []const u8, instructions: []const Ir.Instruction, input: []const u8) !void {
    var reader = Io.Reader.fixed(input);
    var buffer: [256]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);

    var interpreter = IrInterpreter.init(&reader, &writer);
    try interpreter.run(.{ .instructions = instructions });

    try testing.expectEqualStrings(expected, buffer[0..writer.end]);
}

fn expectError(expected: Error, instructions: []const Ir.Instruction) !void {
    var reader = Io.Reader.fixed("");
    var buffer: [256]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);

    var interpreter = IrInterpreter.init(&reader, &writer);

    try testing.expectError(
        expected,
        interpreter.run(.{ .instructions = instructions }),
    );
}

test "add applies its amount to the cell" {
    try expectOutput(
        &.{3},
        &.{
            .{ .add = 3 },
            .write,
        },
        "",
    );
}

test "add wraps on overflow" {
    try expectOutput(
        &.{253},
        &.{
            .{ .add = -3 },
            .write,
        },
        "",
    );
}

test "move applies its amount to the pointer" {
    try expectOutput(
        &.{7},
        &.{
            .{ .move = 2 },
            .{ .add = 7 },
            .write,
        },
        "",
    );
}

test "reading at end of input gives zero" {
    try expectOutput(
        &.{0},
        &.{
            .read,
            .write,
        },
        "",
    );
}

test "loop repeats until the cell is zero" {
    try expectOutput(
        &.{6},
        &.{
            .{ .add = 3 },
            .{ .jump_if_zero = 7 },
            .{ .move = 1 },
            .{ .add = 2 },
            .{ .move = -1 },
            .{ .add = -1 },
            .{ .jump_if_nonzero = 2 },
            .{ .move = 1 },
            .write,
        },
        "",
    );
}

test "moving past the last cell is an error" {
    try expectError(error.PointerOverflow, &.{.{ .move = 40000 }});
}

test "moving before the first cell is an error" {
    try expectError(error.PointerUnderflow, &.{.{ .move = -1 }});
}
