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

/// Compiler `ir` to machine code and runs it to completion.
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
