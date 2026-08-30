<!--
SPDX-FileCopyrightText: 2026 Iyad

SPDX-License-Identifier: Apache-2.0
-->

# brainfuck.zig

A Brainfuck JIT compiler written in Zig.

## Why?

Just for fun.

## Usage

Builds for aarch64 macos only.

```sh
zig build --release=fast
zig-out/bin/bf examples/mandelbrot.bf
```

| Flag       | Effect                             |
| ---------- | ---------------------------------- |
| *(none)*   | walk the ast                       |
| `--ir`     | lower to an ir and interpret that  |
| `--jit`    | compile to machine code and run it |
| `--no-opt` | skip the optimization passes       |

## Benchmarks

Measured on an Apple M4, running `examples/mandelbrot.bf`.

| Engine                       | Command                             | Time  | vs. ast |
| ---------------------------- | ----------------------------------- | ----- | ------- |
| ast interpreter              | `zig build bench`                   | 9.2s  | 1.0x    |
| ir interpreter               | `zig build bench -- --ir --no-opt`  | 7.6s  | 1.2x    |
| ir interpreter + `fold_runs` | `zig build bench -- --ir`           | 2.8s  | 3.3x    |
| jit                          | `zig build bench -- --jit --no-opt` | 2.3s  | 4.0x    |
| jit + `fold_runs`            | `zig build bench -- --jit`          | 0.56s | 16.4x   |

## License

Apache-2.0. See [LICENSE](LICENSE).
