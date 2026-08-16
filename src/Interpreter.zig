// SPDX-FileCopyrightText: 2026 Iyad
//
// SPDX-License-Identifier: Apache-2.0

//! An interpreter that runs the `Ast` directly.
//!
//! The tape is 30000 cells of `u8`, all starting at zero. Cells wrap on overflow,
//! `,` at end of input stores zero, and moving the pointer outside the tape is an
//! error.

const std = @import("std");
const Io = std.Io;
const testing = std.testing;
const Ast = @import("Ast.zig");
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");

const Interpreter = @This();

_tape: [30000]u8,
_pointer: usize,
_reader: *Io.Reader,
_writer: *Io.Writer,

/// An error raised while running a program.
pub const Error = error{
    /// A `>` moved the pointer past the last cell.
    PointerOverflow,

    /// A `<` moved the pointer before the first cell.
    PointerUnderflow,

    /// Reading input failed.
    ReadFailed,

    /// Writing output failed.
    WriteFailed,
};

/// Creates an `Interpreter` where `,` reads from `reader` and `.` writes to `writer`.
///
/// Both must outlive the interpreter.
pub fn init(reader: *Io.Reader, writer: *Io.Writer) Interpreter {
    return .{
        ._tape = @splat(0),
        ._pointer = 0,
        ._reader = reader,
        ._writer = writer,
    };
}

/// Runs `ast` to completion.
///
/// Output is flushed before returning, including when the program fails.
pub fn run(self: *Interpreter, ast: Ast) Error!void {
    defer self._writer.flush() catch {};
    try self.execute(ast.root);
}

fn execute(self: *Interpreter, nodes: []const Ast.Node) Error!void {
    for (nodes) |node| {
        switch (node) {
            .move_right => {
                if (self._pointer == self._tape.len - 1) return error.PointerOverflow;
                self._pointer += 1;
            },
            .move_left => {
                if (self._pointer == 0) return error.PointerUnderflow;
                self._pointer -= 1;
            },
            .increment => self._tape[self._pointer] +%= 1,
            .decrement => self._tape[self._pointer] -%= 1,
            .read => self._tape[self._pointer] = self._reader.takeByte() catch |err|
                switch (err) {
                    error.EndOfStream => 0,
                    else => return error.ReadFailed,
                },
            .write => self._writer.writeByte(self._tape[self._pointer]) catch return error.WriteFailed,
            .loop => |body| while (self._tape[self._pointer] != 0) try self.execute(body),
        }
    }
}

fn expectOutput(expected: []const u8, source: []const u8, input: []const u8) !void {
    const allocator = testing.allocator;

    var lexer = Lexer.init(source);
    var ast = try Parser.parse(allocator, &lexer);
    defer ast.deinit(allocator);

    var reader = Io.Reader.fixed(input);
    var buffer: [1000]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);
    var interpreter = Interpreter.init(&reader, &writer);

    try interpreter.run(ast);

    try testing.expectEqualStrings(expected, buffer[0..writer.end]);
}

fn expectError(expected: Error, source: []const u8) !void {
    const allocator = testing.allocator;

    var lexer = Lexer.init(source);
    var ast = try Parser.parse(allocator, &lexer);
    defer ast.deinit(allocator);

    var reader = Io.Reader.fixed("");
    var buffer: [256]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);
    var interpreter = Interpreter.init(&reader, &writer);

    try testing.expectError(expected, interpreter.run(ast));
}

test "the pointer moves between cells" {
    try expectOutput(&.{ 2, 1 }, "+>++.<.", "");
}

test "increment adds to cell" {
    try expectOutput(&.{3}, "+++.", "");
}

test "decrement subtracts from the cell" {
    try expectOutput(&.{2}, "+++-.", "");
}

test "input is echoed until end of input" {
    try expectOutput("hi!", ",[.,]", "hi!");
}

test "a loop repeats while the cell is non-zero" {
    try expectOutput(&.{6}, "+++[>++<-]>.", "");
}

test "cells wrap on overflow" {
    try expectOutput(&.{ 255, 0 }, "-.+.", "");
}

test "reading at end of input gives 0" {
    try expectOutput(&.{0}, ",.", "");
}

test "moving left of the tape is an error" {
    try expectError(error.PointerUnderflow, "<");
}

test "moving past the tape is an error" {
    try expectError(error.PointerOverflow, "+[>+]");
}

test "a loop can move the pointer" {
    try expectOutput(&.{1}, "+>+>+>[>]<.", "");
}

test "runs hello world" {
    try expectOutput(
        "Hello World!\n",
        "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.",
        "",
    );
}
