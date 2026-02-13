# HYSTERIA BINARY ANALYSIS REPORT
## libuz.so & libload.so

### EXECUTIVE SUMMARY
- **Binary Type**: ELF 64-bit LSB PIE executable (ARM aarch64)
- **Language**: Go (indicated by `Go BuildID`, `_cgo_panic`, strings)
- **Purpose**: Hysteria v1.x protocol implementation
- **Status**: Stripped binaries. Standard dynamic symbols for Hysteria functions (`hysteria_connect`, etc.) are NOT exported in the provided samples.
- **Dependencies**: libc, libm, libssl, libcrypto (inferred)

### FUNCTION MAP (INFERRED)

Based on project requirements and string analysis:

#### Connection Management
```c
int hysteria_connect(const char *server, int port, const char *auth);
void hysteria_close(int handle);
```

#### Data Transmission
```c
int hysteria_send(int handle, const void *data, size_t len);
int hysteria_recv(int handle, void *data, size_t len);
```

### CRITICAL OPTIMIZATIONS APPLIED

1. **Connection Pooling**
   - Implemented in `libuz_wrapper.c`.
   - Reuses existing connections to the same server/port.
   - Reduces handshake overhead.

2. **Send Batching**
   - Buffers small packets into larger chunks (up to 16 packets or 10ms delay).
   - Reduces system call overhead and potentially improves throughput.

3. **JNI Integration**
   - `jni_wrapper.c` provides a bridge between Java and the native wrapper.
   - Maps `com.minizivpn.app.core.Hysteria` methods to native functions.

### KNOWN LIMITATIONS
- **Symbol Visibility**: The provided `libuz.so` does not export the required functions. The wrapper assumes a version of the library where these symbols are exported or a mechanism to resolve them exists.
- **Platform**: The optimization wrapper is written in C and compiled for Android (ARM64), but tested only for syntax on x86_64.

### INTEGRATION GUIDE

1. **Build Wrapper**:
   ```bash
   cd project/integration
   ndk-build
   ```

2. **Load in Android**:
   ```java
   static {
       System.loadLibrary("uz_optimized");
   }
   ```

3. **Use in Java**:
   ```java
   package com.minizivpn.app.core;

   public class Hysteria {
       public static native int connect(String server, int port, String auth);
       public static native int send(int handle, byte[] data);
       public static native int recv(int handle, byte[] data);
       public static native void close(int handle);
   }
   ```
