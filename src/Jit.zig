// SPDX-FileCopyrightText: 2026 Iyad
//
// SPDX-License-Identifier: Apache-2.0

//! Runs an `Ir` by compiling it to machine code and calling that.
//!
//! Semantics match `Interpreter` and `IrInterpreter`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const posix = std.posix;
const Io = std.Io;
const testing = std.testing;
const Runtime = @import("Jit/runtime.zig").Runtime;
const Ir = @import("Ir.zig");
const codegen = @import("codegen.zig");
const JitBuffer = @import("JitBuffer.zig");

const Jit = @This();

_tape: [30000]u8,
_runtime: Runtime,
_allocator: Allocator,

/// An error raised while compiling or running a program.
pub const Error = RunError || CompileError;

/// An error raised while turning a program into machine code.
pub const CompileError = Allocator.Error || posix.MMapError;

/// An error raised while running a program.
pub const RunError = codegen.Error || Runtime.Error;

/// Creates a `Jit` where `read` takes from `reader` and `write` goes to `writer`.
///
/// Both must outlive the jit.
pub fn init(allocator: Allocator, reader: *Io.Reader, writer: *Io.Writer) Jit {
    return .{
        ._tape = @splat(0),
        ._runtime = Runtime.init(reader, writer),
        ._allocator = allocator,
    };
}

/// Compiles `ir` to machine code and runs it to completion.
///
/// Output is flushed before returning, including when the program fails.
pub fn run(self: *Jit, ir: Ir) Error!void {
    const code = try codegen.generate(self._allocator, ir);
    defer self._allocator.free(code);

    var buffer = try JitBuffer.init(code);
    defer buffer.deinit();

    const status: codegen.Status = @enumFromInt(buffer.call(
        &self._tape,
        &self._runtime,
    ));
    self._runtime.flush();

    try self._runtime.check();
    try status.toError();
}

fn expectOutput(expected: []const u8, instructions: []Ir.Instruction, input: []const u8) !void {
    var reader = Io.Reader.fixed(input);
    var buffer: [256]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);

    var jit = Jit.init(testing.allocator, &reader, &writer);
    try jit.run(.{ .instructions = instructions });

    try testing.expectEqualStrings(expected, buffer[0..writer.end]);
}

fn expectError(expected: Error, instructions: []Ir.Instruction) !void {
    var reader = Io.Reader.fixed("");
    var buffer: [256]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);

    var jit = Jit.init(testing.allocator, &reader, &writer);

    try testing.expectError(
        expected,
        jit.run(.{ .instructions = instructions }),
    );
}

test "add applies its amount to the cell" {
    var instructions = [_]Ir.Instruction{
        .{ .add = 3 },
        .write,
    };
    try expectOutput(&.{3}, &instructions, "");
}

test "add wraps on overflow" {
    var instructions = [_]Ir.Instruction{
        .{ .add = 253 },
        .{ .add = 5 },
        .write,
    };
    try expectOutput(&.{2}, &instructions, "");
}

test "move applies its amount to the pointer" {
    var instructions = [_]Ir.Instruction{
        .{ .move = 2 },
        .{ .add = 7 },
        .write,
    };
    try expectOutput(&.{7}, &instructions, "");
}

test "move takes the pointer back" {
    var instructions = [_]Ir.Instruction{
        .{ .add = 1 },
        .{ .move = 5 },
        .{ .move = -5 },
        .write,
    };
    try expectOutput(&.{1}, &instructions, "");
}

test "reading at end of input gives zero" {
    var instructions = [_]Ir.Instruction{
        .read,
        .write,
    };
    try expectOutput(&.{0}, &instructions, "");
}

test "reading takes from the input" {
    var instructions = [_]Ir.Instruction{
        .read,
        .write,
        .read,
        .write,
    };
    try expectOutput("hi", &instructions, "hi");
}

test "loop repeats until the cell is zero" {
    var instructions = [_]Ir.Instruction{
        .{ .add = 3 },
        .{ .jump_if_zero = 7 },
        .{ .move = 1 },
        .{ .add = 2 },
        .{ .move = -1 },
        .{ .add = 255 },
        .{ .jump_if_nonzero = 2 },
        .{ .move = 1 },
        .write,
    };
    try expectOutput(&.{6}, &instructions, "");
}

test "loop is skipped when the cell is already zero" {
    var instructions = [_]Ir.Instruction{
        .{ .jump_if_zero = 3 },
        .{ .add = 9 },
        .{ .jump_if_nonzero = 1 },
        .{ .add = 1 },
        .write,
    };
    try expectOutput(&.{1}, &instructions, "");
}

test "moving past the last cell is an error" {
    var instructions = [_]Ir.Instruction{.{ .move = 40000 }};
    try expectError(error.PointerOverflow, &instructions);
}

test "moving before the first cell is an error" {
    var instructions = [_]Ir.Instruction{.{ .move = -1 }};
    try expectError(error.PointerUnderflow, &instructions);
}

test "a move far past the tape is still an error" {
    var right = [_]Ir.Instruction{.{ .move = 70000 }};
    try expectError(error.PointerOverflow, &right);

    var left = [_]Ir.Instruction{.{ .move = -70000 }};
    try expectError(error.PointerUnderflow, &left);
}

test "output written before an error is kept" {
    var instructions = [_]Ir.Instruction{
        .{ .add = 4 },
        .write,
        .{ .move = -1 },
    };

    var reader = Io.Reader.fixed("");
    var buffer: [256]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);

    var jit = Jit.init(testing.allocator, &reader, &writer);

    try testing.expectError(
        error.PointerUnderflow,
        jit.run(.{ .instructions = &instructions }),
    );
    try testing.expectEqualStrings(&.{4}, buffer[0..writer.end]);
}

test "a move of any magnitude lands on the right cell" {
    for ([_]i32{ 1, 4095, 4096, 4097, 29999 }) |n| {
        errdefer std.debug.print("failed at move {d}\n", .{n});

        var instructions = [_]Ir.Instruction{
            .{ .add = 9 },
            .{ .move = n },
            .{ .add = 1 },
            .write,
        };
        try expectOutput(&.{1}, &instructions, "");
    }
}

test "a move of any magnitude comes back" {
    for ([_]i32{ 1, 4095, 4096, 4097, 29999 }) |n| {
        errdefer std.debug.print("failed at move {d}\n", .{n});

        var instructions = [_]Ir.Instruction{
            .{ .move = n },
            .{ .add = 9 },
            .{ .move = -n },
            .{ .add = 1 },
            .write,
        };
        try expectOutput(&.{1}, &instructions, "");
    }
}
