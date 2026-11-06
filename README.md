# rsa-wasm

RSA PKCS#1 v1.5 signatures with SHA-256, written in Zig, and tuned for WebAssembly with the wide-arithmetic extension.

It supports 2048, 3072 and 4096-bit keys.
The size is picked at build time with `-Dbits=N` (default 4096), so each build is fully specialized for it.

## Benchmarks

`BENCHMARK-RSA4096.md` compares RSA-4096 signing and verification with the Rust `rsa` crate (0.10), zig-rsa and OpenSSL.

They run on an Apple M5 Max and on an AMD Ryzen 7 7700 with boost turned off.
OpenSSL runs natively, and the others run natively and on wasm, with wasmer's Cranelift and LLVM backends.

Signing, in ms, with wide arithmetic on wasm:

```
+---------+------------------+----------------+-------------+----------------+-------------+----------------+
| host    | runtime          | rsa-wasm no-ct | rsa-wasm ct | rsa 0.10 no-ct | rsa 0.10 ct | OpenSSL ct     |
+---------+------------------+----------------+-------------+----------------+-------------+----------------+
| aarch64 | native           |           2.03 |        2.26 |           3.88 |        5.47 |           1.82 |
| aarch64 | wasmer cranelift |           2.17 |        2.43 |           5.35 |        7.48 |              - |
| aarch64 | wasmer llvm      |           2.29 |        2.46 |           5.11 |        7.09 |              - |
| x86_64  | native           |           4.69 |        5.11 |           9.26 |       12.69 | 1.39 (3.88)    |
| x86_64  | wasmer cranelift |           5.02 |        5.92 |          11.73 |       16.26 |              - |
| x86_64  | wasmer llvm      |           5.24 |        6.10 |          12.28 |       16.73 |              - |
+---------+------------------+----------------+-------------+----------------+-------------+----------------+
```

On x86_64, OpenSSL uses AVX-512 IFMA, and the number in parentheses is without it.

"ct" means with side-channel mitigations: constant-time code for rsa-wasm, blinding for rsa 0.10, and both for OpenSSL.
rsa 0.10 is always constant time, so its "no-ct" column is constant time without blinding.

## Constant-time signing

By default, signing doesn't run in constant time, so that it's as fast as possible.
To make it constant time:

```sh
zig build -Dside-channels-mitigations=medium   # any level other than none
```

At 4096 bits, that costs 7 to 12% on the M5, and 7 to 18% on the Ryzen, depending on the runtime.

`tmp/ct/` has the checks that signing really runs in constant time.

## How it's fast

Natively and on wasm with wide arithmetic, Montgomery multiplication and squaring compute the product one column at a time, and reduce in the same columns.
That's used up to 32 limbs, which covers signing with every key size, and verification with 2048-bit keys.
Verification with larger keys also squares by columns, but reduces row by row.

The code is fully unrolled for each key size, and written so that Cranelift doesn't have to spill the intermediate values.

Without wide arithmetic, simpler row-by-row code is used, because it's faster there.

`findings.md` explains how this works, and what else was tried.
