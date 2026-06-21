
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

## Comptime key vs. runtime key

The numbers above bake the signing key into the binary at compile time, so the
modulus limbs become immediates in the Montgomery loops. Building with
`-Druntime_key=true` instead parses the key from its hex form at startup and
passes it to `sign()` as an ordinary argument, the same way the message is — the
modulus is then opaque to the optimizer. Key parsing and the one-time Montgomery
setup happen before the timed loop. Measured best-of-12 by timing two iteration
counts and subtracting (so startup, instantiation and key setup all cancel):

| key form     | native ms/sign | wasm ms/sign |
| ------------ | -------------- | ------------ |
| comptime     | 3.08           | 3.23         |
| runtime arg  | 2.96           | 3.34         |

A runtime modulus costs about 3-4% on wasm and nothing measurable on native:
the comptime key only helps because LLVM can fold the modulus into the inner
loops, and that win shows up on wasm but is drowned out by the hardware 64×64
multiply on native.
