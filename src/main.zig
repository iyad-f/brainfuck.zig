// SPDX-FileCopyrightText: 2026 Iyad
//
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const process = std.process;
const Io = std.Io;
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");
const Interpreter = @import("Interpreter.zig");

pub fn main(init: process.Init) void {
    var args = init.minimal.args.iterate();
    _ = args.skip();

    const path = args.next() orelse process.fatal(
        "usage: bf <file.bf>",
        .{},
    );

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

    var interpreter = Interpreter.init(stdin, stdout);
    interpreter.run(ast) catch |err| switch (err) {
        error.PointerOverflow => process.fatal("the pointer moved past the last cell", .{}),
        error.PointerUnderflow => process.fatal("the pointer moved before the first cell", .{}),
        error.ReadFailed => process.fatal("reading input failed", .{}),
        error.WriteFailed => process.fatal("writing output failed", .{}),
    };
}

test {
    _ = @import("Lexer.zig");
    _ = @import("Ast.zig");
    _ = @import("Parser.zig");
    _ = @import("Interpreter.zig");
}
