// SPDX-FileCopyrightText: 2026 Iyad
//
// SPDX-License-Identifier: Apache-2.0

//! An intermediate representation of a brainfuck program.

const Allocator = @import("std").mem.Allocator;

const Ir = @This();

/// The instructions of the program, in order.
instructions: []const Instruction,

/// A single step of the program.
pub const Instruction = union(enum) {
    /// Moves the pointer by this many cells.
    ///
    /// Use negative values to move left.
    move: i32,

    /// Adds to the cell under the pointer.
    ///
    /// Use negative values for subtraction.
    add: i8,

    /// Reads a byte into the cell under the pointer.
    read,

    /// Writes out the cell under the pointer.
    write,

    /// Jumps if the cell under the pointer is zero.
    ///
    /// The target is the instruction after the matching `]`.
    jump_if_zero: usize,

    /// Jumps if the cell under the pointer is non-zero
    ///
    /// The target is the instruction after the matching `[`.
    jump_if_nonzero: usize,
};

/// Frees all alocatoed memory and invalidates this ir.
pub fn deinit(self: *Ir, allocator: Allocator) void {
    allocator.free(self.instructions);
    self.* = undefined;
}
