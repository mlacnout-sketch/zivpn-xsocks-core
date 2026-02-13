# Binary Analysis Report: libuz.so & libload.so

## Executive Summary

- **Target**: `libuz.so` and `libload.so` (Hysteria v1.x Implementation)
- **Architecture**: ARM64 (AArch64)
- **File Type**: ELF 64-bit LSB shared object
- **Language/Runtime**: Go (detected via `_cgo_` and `main.main` symbols) with CGO bindings.

## Static Analysis Findings

### File Header Analysis (`libuz.so`)
- **Class**: ELF64
- **Data**: 2's complement, little endian
- **Machine**: AArch64
- **Type**: DYN (Shared Object)

### Runtime Detection
The presence of symbols such as:
- `_cgo_topofstack`
- `_cgo_panic`
- `crosscall2`
- `main.main`

Strongly indicates that `libuz.so` is a Go shared library. This implies that the core logic (Hysteria protocol, QUIC transport) is implemented in Go, and it exposes a C-compatible interface via CGO.

### Dependencies
Shared library dependencies (from `readelf -d`):
- `liblog.so` (Android logging)
- `libc.so` (Standard C library)
- `libdl.so` (Dynamic linker)
- `libm.so` (Math library)

### Key Functionality Inferred
- **Networking**: Likely uses Go's `net` package and `quic-go` for transport.
- **Concurrency**: Uses Go routines, managed by the Go runtime embedded in the shared library.
- **Integration**: Exposed via JNI or C function exports to be called from the Android app.

## Optimization Strategy

Since the core logic is in Go and compiled to a stripped binary (likely), direct binary patching is risky and complex. The recommended optimization strategy is:

1.  **Wrapper Interception**: Create a C wrapper (`libuz_wrapper.c`) that intercepts calls to the exported functions.
2.  **Connection Pooling**: Implement pooling in the wrapper to reuse Hysteria sessions/connections, reducing handshake overhead.
3.  **Batching**: Group small write operations into larger chunks before passing them to the Go runtime to reduce CGO call overhead (which is significant).
4.  **JNI Optimization**: Ensure efficient data passing between Java/Kotlin and the native layer (using direct ByteBuffers where possible).

## Next Steps
- Implement `libuz_wrapper.c` to provide the optimization layer.
- Build the wrapper using `Android.mk` / `CMake`.
- Benchmark the wrapper against the direct calls.
