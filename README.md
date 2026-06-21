
# RSA-4096 signing benchmarks

PKCS#1 v1.5 signatures over SHA-256 with a 4096-bit key. Every implementation
produces the same signature bytes; the only thing that varies is how fast it
gets there. The Wasm rows run under Wasmtime with precompiled modules.

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

## Comptime key vs. runtime key

The numbers above bake the signing key into the binary at compile time, so the
modulus limbs become immediates in the Montgomery loops. Building with
`-Druntime_key=true` instead parses the key from its hex form at startup and
passes it to `sign()` as an ordinary argument, the same way the
message is: the modulus is then opaque to the optimizer.

| key form    | wasm ms/sign |
| ----------- | ------------ |
| comptime    | 3.23         |
| runtime arg | 3.34         |

A runtime modulus costs about 3-4% on wasm and nothing measurable on native.
