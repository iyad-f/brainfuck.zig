// SPDX-FileCopyrightText: 2026 Iyad
//
// SPDX-License-Identifier: Apache-2.0

//! Command-line argument parsing.

const std = @import("std");
const mem = std.mem;
const testing = std.testing;

/// The result of a successful `parse`.
pub const Parsed = struct {
    /// The path of the program to run.
    path: []const u8,

    /// Options that control how the program is run.
    options: Options,
};

/// Options that control how the program is run.
pub const Options = struct {
    /// Runs the program through the ir interpreter.
    use_ir: bool = false,

    /// Skips the optimization passes, running the ir exactly as lowered.
    no_opt: bool = false,
};

/// Errors `parse` can return.
pub const ParseError = error{
    /// No program path was given.
    MissingPath,

    /// An option was given which was not recognized.
    UnknownOption,

    /// An unexpected argument was given.
    UnexpectedArgument,
};

/// Parses `args` into a `Parsed`.
///
/// `args` is the full argument list, so index 0 is the program name and is
/// skipped. Options may come before or after the program path.
///
/// The result borrows from `args`, so it stays valid only as long as `args` does.
pub fn parse(args: []const [:0]const u8) ParseError!Parsed {
    var path: ?[]const u8 = null;
    var options = Options{};

    for (args[1..]) |arg| {
        if (mem.startsWith(u8, arg, "-")) {
            if (mem.eql(u8, arg, "--ir"))
                options.use_ir = true
            else if (mem.eql(u8, arg, "--no-opt"))
                options.no_opt = true
            else
                return error.UnknownOption;
        } else {
            if (path != null) return error.UnexpectedArgument;
            path = arg;
        }
    }

    return .{
        .path = path orelse return error.MissingPath,
        .options = options,
    };
}

fn expectParsed(expected: Parsed, args: []const [:0]const u8) !void {
    try testing.expectEqualDeep(expected, try parse(args));
}

fn expectParseError(expected: ParseError, args: []const [:0]const u8) !void {
    try testing.expectError(expected, parse(args));
}

test "path is parsed with default options" {
    try expectParsed(
        .{ .path = "a.bf", .options = .{} },
        &.{ "bf", "a.bf" },
    );
}

test "option before the path is parsed" {
    try expectParsed(
        .{ .path = "a.bf", .options = .{ .use_ir = true } },
        &.{ "bf", "--ir", "a.bf" },
    );
}

test "option after the path is parsed" {
    try expectParsed(
        .{ .path = "a.bf", .options = .{ .use_ir = true } },
        &.{ "bf", "a.bf", "--ir" },
    );
}

test "no path is an error" {
    try expectParseError(error.MissingPath, &.{"bf"});
}

test "second path is an error" {
    try expectParseError(error.UnexpectedArgument, &.{ "bf", "a.bf", "b.bf" });
}

test "unrecognized option is an error" {
    try expectParseError(error.UnknownOption, &.{ "bf", "--unknown", "a.bf" });
}

test "no-opt is parsed" {
    try expectParsed(
        .{ .path = "a.bf", .options = .{ .use_ir = true, .no_opt = true } },
        &.{ "bf", "--ir", "--no-opt", "a.bf" },
    );
}
