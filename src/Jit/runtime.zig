// SPDX-FileCopyrightText: 2026 Iyad
//
// SPDX-License-Identifier: Apache-2.0

//! The host functions jitted code calls into.

const std = @import("std");
const debug = std.debug;
const Io = std.Io;

/// The functions and streams jitted code has access to.
///
/// This is an extern struct because the generated code loads `write` and `read`
/// by offset, and it reads them with the c calling convention.
pub const Runtime = extern struct {
    write: *const fn (*Runtime, u8) callconv(.c) void,
    read: *const fn (*Runtime) callconv(.c) u8,
    _writer: *Io.Writer,
    _reader: *Io.Reader,
    _failure: Failure,

    comptime {
        debug.assert(@offsetOf(Runtime, "write") == 0);
        debug.assert(@offsetOf(Runtime, "read") == 8);
    }

    /// An error raised by a host call.
    pub const Error = error{
        /// Reading input failed.
        ReadFailed,

        /// Writing output failed.
        WriteFailed,
    };

    /// How a host call failed.
    const Failure = enum(u8) {
        none,
        read,
        write,
    };

    /// Creates a `Runtime` where `read` takes from `reader` and `write` goes to `writer`.
    ///
    /// Both must outlive the runtime.
    pub fn init(reader: *Io.Reader, writer: *Io.Writer) Runtime {
        return .{
            .write = hostWrite,
            .read = hostRead,
            ._reader = reader,
            ._writer = writer,
            ._failure = .none,
        };
    }

    /// Flushes buffered output, recording a failure instead of returning it.
    pub fn flush(self: *Runtime) void {
        self._writer.flush() catch {
            self._failure = .write;
        };
    }

    /// Returns an error from a failed host call, if there was one.
    pub fn check(self: Runtime) Error!void {
        return switch (self._failure) {
            .none => {},
            .read => error.ReadFailed,
            .write => error.WriteFailed,
        };
    }

    /// Writes `byte`, recording the failure instead of returning it.
    fn hostWrite(self: *Runtime, byte: u8) callconv(.c) void {
        self._writer.writeByte(byte) catch {
            self._failure = .write;
        };
    }

    /// Reads a byte, yielding 0 at the end of the input.
    fn hostRead(self: *Runtime) callconv(.c) u8 {
        return self._reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => 0,
            else => {
                self._failure = .read;
                return 0;
            },
        };
    }
};
