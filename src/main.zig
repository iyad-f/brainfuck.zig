// SPDX-FileCopyrightText: 2026 Iyad
//
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const process = std.process;
const Io = std.Io;
const cli = @import("cli.zig");
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");
const Interpreter = @import("Interpreter.zig");
const Lowering = @import("Lowering.zig");
const IrInterpreter = @import("IrInterpreter.zig");
const foldRuns = @import("passes/fold_runs.zig").foldRuns;
const Jit = @import("Jit.zig");

pub fn main(init: process.Init) void {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch |err|
        process.fatal("cannot read arguments: {t}", .{err});

    const parsed = cli.parse(args) catch |err| switch (err) {
        error.MissingPath => process.fatal("usage: bf [--ir] <file.bf>", .{}),
        error.UnknownOption => process.fatal("unknown option", .{}),
        error.UnexpectedArgument => process.fatal("unexpected argument", .{}),
    };
    const path = parsed.path;

    const io = init.io;
    const gpa = init.gpa;

    const source = Io.Dir.cwd().readFileAlloc(
        io,
        path,
        gpa,
        .unlimited,
    ) catch |err| process.fatal("cannot read '{s}': {t}", .{ path, err });
    defer gpa.free(source);

    var lexer = Lexer.init(source);
    var ast = Parser.parse(gpa, &lexer) catch |err| switch (err) {
        error.MissingRightBracket => process.fatal("missing right bracket", .{}),
        error.UnexpectedRightBracket => process.fatal("unexpected right bracket", .{}),
        error.OutOfMemory => process.fatal("out of memory", .{}),
    };
    defer ast.deinit(gpa);

    var stdin_buffer: [1024 * 4]u8 = undefined;
    var stdin_reader = Io.File.stdin().reader(io, &stdin_buffer);
    const stdin = &stdin_reader.interface;

    var stdout_buffer: [1024 * 4]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    if (parsed.options.use_ir or parsed.options.use_jit) {
        var ir = Lowering.lower(gpa, ast) catch |err| switch (err) {
            error.OutOfMemory => process.fatal("out of memory", .{}),
        };
        defer ir.deinit(gpa);

        if (!parsed.options.no_opt) {
            _ = foldRuns(gpa, &ir) catch |err| switch (err) {
                error.OutOfMemory => process.fatal("out of memory", .{}),
            };
        }

        if (parsed.options.use_jit) {
            var jit = Jit.init(gpa, stdin, stdout);
            jit.run(ir) catch |err| handleRunError(err);
        } else {
            var interpreter = IrInterpreter.init(stdin, stdout);
            interpreter.run(ir) catch |err| handleRunError(err);
        }
    } else {
        var interpreter = Interpreter.init(stdin, stdout);
        interpreter.run(ast) catch |err| handleRunError(err);
    }
}

/// Reports why a program could not be run and exits.
fn handleRunError(err: (Interpreter.Error || IrInterpreter.Error || Jit.Error)) noreturn {
    switch (err) {
        error.PointerOverflow => process.fatal("the pointer moved past the last cell", .{}),
        error.PointerUnderflow => process.fatal("the pointer moved before the first cell", .{}),
        error.ReadFailed => process.fatal("reading input failed", .{}),
        error.WriteFailed => process.fatal("writing output failed", .{}),
        error.OutOfMemory => process.fatal("out of memory", .{}),
        else => process.fatal("cannot map executable memory: {t}", .{err}),
    }
}

test {
    _ = @import("cli.zig");
    _ = @import("Lexer.zig");
    _ = @import("Ast.zig");
    _ = @import("Parser.zig");
    _ = @import("Interpreter.zig");
    _ = @import("Ir.zig");
    _ = @import("Lowering.zig");
    _ = @import("IrInterpreter.zig");
    _ = @import("passes/fold_runs.zig");
    _ = @import("codegen.zig");
    _ = @import("codegen/aarch64.zig");
    _ = @import("JitBuffer.zig");
    _ = @import("Jit/runtime.zig");
    _ = @import("Jit.zig");
}
