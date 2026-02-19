# Changelog

All notable changes to this project will be documented in this file.

## [1.0.27] - 2026-02-19

### Added
- Integrated lexpesawat AutoPilot with Shizuku integration for seamless Airplane Mode toggling.
- Real-time PING latency display in dynamic status bar icon (Native Bitmap Rendering).
- Support for multiple DNS gateways with Round-Robin distribution in tun2socks.
- Explicit CNAME loop detection in pdnsd to prevent infinite recursion.
- Persistent background monitoring service with watchdog priority hardening.
- Memory pooling for `Connection` struct in tun2socks to reduce allocation overhead.
- Iterative CIDR-based routing logic in `RoutingUtils.kt` for 100% precision in IP exclusion.

### Fixed
- Migrated all `sprintf` calls to `snprintf` in lemon parser and pdnsd cache for buffer overflow protection.
- Added MTU bounds checking in tun2socks DNS packet handling to prevent heap overflow.
- Resolved DNS loop issues by exempting DNS gateway IP from hijacking.
- Fixed upstream DNS synchronization by passing correct parameters from Flutter to Native.
- Cleaned up unused imports and fields in Dart and Kotlin code.

### Changed
- Default upstream DNS changed to Google DNS (8.8.8.8) for better stability.
- Reduced default TTL and enabled cache purging in pdnsd for fresher data.
- Enhanced GitHub Actions workflow with linting, native build checks, and separate ABI artifacts.
- Improved UI with activity logs and better status visualization.
