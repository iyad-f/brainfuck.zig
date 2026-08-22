<!--
SPDX-FileCopyrightText: 2026 Iyad

SPDX-License-Identifier: Apache-2.0
-->

# brainfuck.zig

A Brainfuck JIT compiler written in Zig.

## Why?

Just for fun.

## Benchmarks

Measured on an Apple M4 with `zig build bench [-- flags]`, running `examples/mandelbrot.bf`.

| Engine                           | Time | Speedup |
| -------------------------------- | ---- | ------- |
| ast interpreter                  | 9.2s | 1.0x    |
| ir interpreter (`--ir --no-opt`) | 7.6s | 1.2x    |
| + `fold_runs` (`--ir`)           | 2.8s | 3.3x    |

## License

Apache-2.0. See [LICENSE](LICENSE).
