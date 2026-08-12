// SPDX-FileCopyrightText: 2026 Iyad
//
// SPDX-License-Identifier: Apache-2.0

//! A lexer producing tokens from source text.

const std = @import("std");
const testing = std.testing;

const Lexer = @This();

_source: []const u8,
_pos: usize,

/// Creates a `Lexer` for `source`.
///
/// `source` must outlive the lexer.
pub fn init(source: []const u8) Lexer {
    return .{
        ._source = source,
        ._pos = 0,
    };
}

/// Returns the next token.
///
/// Ignores characters which are not a brainfuck command.
pub fn next(self: *Lexer) Token {
    while (self._pos < self._source.len) {
        const curr = self._pos;
        self._pos += 1;

        const kind: TokenKind = switch (self._source[curr]) {
            '>' => .angle_bracket_right,
            '<' => .angle_bracket_left,
            '+' => .plus,
            '-' => .minus,
            ',' => .comma,
            '.' => .dot,
            '[' => .l_bracket,
            ']' => .r_bracket,
            else => continue, // if we dont recognize the token we simply ignore it.
        };

        return .{ .kind = kind, .position = curr };
    }

    return .{
        .kind = .eof,
        .position = self._pos,
    };
}

/// The kind of a token.
pub const TokenKind = enum {
    /// The `>` command.
    angle_bracket_right,

    /// The `<` command.
    angle_bracket_left,

    /// The `+` command.
    plus,

    /// The `-` command.
    minus,

    /// The `,` command.
    comma,

    /// The `.` command.
    dot,

    /// The `[` command.
    l_bracket,

    /// The `]` command.
    r_bracket,

    /// Indicates that the end of source has been reached.
    eof, // end of file
};

/// A brainfuck command and where it was found in the source.
pub const Token = struct {
    /// The kind of token.
    kind: TokenKind,

    /// The zero-based byte offset of the command in the source.
    position: usize,
};

test "given source tokens get correct kind" {
    const source: []const u8 = "><+-,.[]";
    var lexer = Lexer.init(source);

    try testing.expectEqual(.angle_bracket_right, lexer.next().kind);
    try testing.expectEqual(.angle_bracket_left, lexer.next().kind);
    try testing.expectEqual(.plus, lexer.next().kind);
    try testing.expectEqual(.minus, lexer.next().kind);
    try testing.expectEqual(.comma, lexer.next().kind);
    try testing.expectEqual(.dot, lexer.next().kind);
    try testing.expectEqual(.l_bracket, lexer.next().kind);
    try testing.expectEqual(.r_bracket, lexer.next().kind);
    try testing.expectEqual(.eof, lexer.next().kind);
}

test "given source tokens get correct position" {
    const source: []const u8 = "><+-,.[]";
    var lexer = Lexer.init(source);

    for (0..8) |i| {
        try testing.expectEqual(i, lexer.next().position);
    }
}

test "empty source gets eof" {
    const source: []const u8 = "";
    var lexer = Lexer.init(source);

    try testing.expectEqualDeep(
        Token{ .kind = .eof, .position = 0 },
        lexer.next(),
    );
}

test "non brainfuck command characters are ignored" {
    const source: []const u8 = "<hello>";
    var lexer = Lexer.init(source);

    try testing.expectEqualDeep(
        Token{ .kind = .angle_bracket_left, .position = 0 },
        lexer.next(),
    );
    try testing.expectEqualDeep(
        Token{ .kind = .angle_bracket_right, .position = 6 },
        lexer.next(),
    );
    try testing.expectEqualDeep(
        Token{ .kind = .eof, .position = 7 },
        lexer.next(),
    );
}
