# rsa-wasm

RSA PKCS#1 v1.5 signatures with SHA-256, written in Zig, and tuned for WebAssembly with the wide-arithmetic extension.

It supports 2048, 3072 and 4096-bit keys.
The size is picked at build time with `-Dbits=N` (default 4096), so each build is fully specialized for it.

## Benchmarks

`BENCHMARK-RSA4096.md` compares RSA-4096 signing and verification with the Rust `rsa` crate (0.10), zig-rsa and OpenSSL.

They run on an Apple M5 Max and on an AMD Ryzen 7 7700 with boost turned off.

Everything runs natively and on wasm, with wasmer's Cranelift and LLVM backends.
On wasm, OpenSSL is the build from openssl-wasi, which has no assembly.

Signing, in ms, with wide arithmetic on wasm:

```
+---------+------------------+----------------+-------------+----------------+-------------+----------------+
| host    | runtime          | rsa-wasm no-ct | rsa-wasm ct | rsa 0.10 no-ct | rsa 0.10 ct | OpenSSL ct     |
+---------+------------------+----------------+-------------+----------------+-------------+----------------+
| aarch64 | native           |           2.05 |        2.29 |           3.90 |        5.55 |           1.83 |
| aarch64 | wasmer cranelift |           2.21 |        2.45 |           5.43 |        7.61 |           7.79 |
| aarch64 | wasmer llvm      |           2.29 |        2.45 |           5.16 |        7.15 |           6.41 |
| x86_64  | native           |           4.75 |        5.14 |           9.26 |       12.68 | 1.39 (3.88)    |
| x86_64  | wasmer cranelift |           4.89 |        5.91 |          11.72 |       16.25 |          13.15 |
| x86_64  | wasmer llvm      |           5.21 |        6.06 |          12.28 |       16.72 |          11.16 |
+---------+------------------+----------------+-------------+----------------+-------------+----------------+
```

On x86_64, native OpenSSL uses AVX-512 IFMA, and the number in parentheses is without it.

Without wide arithmetic, with SIMD:

```
+---------+------------------+----------------+-------------+----------------+-------------+----------------+
| host    | runtime          | rsa-wasm no-ct | rsa-wasm ct | rsa 0.10 no-ct | rsa 0.10 ct | OpenSSL ct     |
+---------+------------------+----------------+-------------+----------------+-------------+----------------+
| aarch64 | wasmer cranelift |           5.36 |        5.87 |          17.69 |       23.35 |          15.54 |
| aarch64 | wasmer llvm      |           5.01 |        5.20 |          14.99 |       19.77 |          18.05 |
| x86_64  | wasmer cranelift |          14.82 |       15.65 |          58.22 |       76.87 |          29.67 |
| x86_64  | wasmer llvm      |          10.97 |       11.48 |          40.85 |       53.99 |          26.15 |
+---------+------------------+----------------+-------------+----------------+-------------+----------------+
```

"ct" means with side-channel mitigations: constant-time code for rsa-wasm, blinding for rsa 0.10, and both for OpenSSL.
rsa 0.10 is always constant time, so its "no-ct" column is constant time without blinding.

## Constant-time signing

By default, signing doesn't run in constant time, so that it's as fast as possible.
To make it constant time:

```sh
zig build -Dside-channels-mitigations=medium   # any level other than none
```

At 4096 bits, that costs 4 to 12% on the M5, and 5 to 21% on the Ryzen, depending on the runtime.

`tmp/ct/` has the checks that signing really runs in constant time.

## How it's fast

Natively and on wasm with wide arithmetic, Montgomery multiplication and squaring compute the product one column at a time, and reduce in the same columns.
That's used up to 32 limbs, which covers signing with every key size, and verification with 2048-bit keys.
Verification with larger keys also squares by columns, but reduces row by row.

The code is fully unrolled for each key size, and written so that Cranelift doesn't have to spill the intermediate values.

Without wide arithmetic, signing uses 28-bit limbs, an idea taken from OpenSSL's RSAZ code.

Each product is then a single multiply, and nothing has to carry until the end of a column.
With SIMD, p and q are worked on together, one in each lane.

Verification still uses 64-bit limbs there.

`findings.md` explains how this works, and what else was tried.
