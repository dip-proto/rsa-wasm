
# RSA-4096 signing benchmarks

PKCS#1 v1.5 signatures over SHA-256 with a 4096-bit key. Every implementation
produces the same signature bytes; the only thing that varies is how fast it
gets there. The Wasm rows run under Wasmtime with precompiled modules.

The signer is parametric over the modulus size: 2048, 3072 and 4096 bits all
work, selected at build time with `-Dbits=N` (default 4096). The size is a
comptime parameter, so each build is fully specialized — the 4096-bit path
compiles to exactly the same code it did before the other sizes existed. The
benchmark numbers below are all for the 4096-bit key.

## Apple Silicon M5 (aarch64)

| Implementation                | ms/sign | vs OpenSSL native |
| ----------------------------- | ------- | ----------------- |
| OpenSSL native (asm)          | 1.93    | 1.00x             |
| BoringSSL native (asm)        | 2.05    | 1.06× slower      |
| Zig native                    | 3.21    | 1.66× slower      |
| Zig wasm — wide-arithmetic    | 3.43    | 1.78× slower      |
| Zig wasm — no wide-arithmetic | 8.32    | 4.31× slower      |
| BoringSSL wasm (precompiled)  | 13.98   | 7.24× slower      |
| Rust `rsa` 0.9.10 wasm        | 20.00   | 10.4× slower      |
| Rust `rsa` 0.10 wasm          | 21.79   | 11.3× slower      |
| OpenSSL 3 wasm (precompiled)  | 38.65   | 20.0× slower      |

## Linux/x86_64 (AMD Zen 5)

Rerun on an AMD Ryzen AI 9 HX 470 (Zen 5) under Linux, again with Wasmtime and
precompiled modules. Frequency boost was disabled and the CPU was capped at
2.0 GHz on this host, so the absolute times run much higher than the M5 numbers
above and the two machines are not directly comparable. What is comparable is
the spread between implementations, and here it is far wider.

| Implementation             | ms/sign | vs OpenSSL native |
| -------------------------- | ------- | ----------------- |
| OpenSSL native (asm)       | 2.72    | 1.00x             |
| Zig wasm — wide-arithmetic | 11.30   | 4.15× slower      |
| Rust `rsa` 0.9.10 wasm     | 106.57  | 39.2× slower      |
| Rust `rsa` 0.10 wasm       | 106.57  | 39.2× slower      |

