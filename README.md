
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
