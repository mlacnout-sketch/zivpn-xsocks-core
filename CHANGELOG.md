# Changelog

## [1.0.26] - 2026-02-17

### Added
- **Smart Preset V2 (Strict & Fluid):** New dynamic network tuning that analyzes RSRP, SINR, and Frequency Band (EARFCN) to calculate precise `recvwindow` sizes.
- **Fluid Dynamic Tuning:** Replaced static presets with a linear calculation formula for unique, per-KB buffer optimization.
- **Resilient Updater:** Added a 3-layer fallback strategy for self-updates (Native VPN Binding, SOCKS5, and Direct) allowing the app to use its own tunnel for updates.
- **Multi-ABI Support:** Added `armeabi-v7a` support in build workflows and included 32-bit native libraries.
- **Standardized Splash Screen:** Dark theme splash with MiniZIVPN logo for all Android versions.

### Fixed
- **Security:** Resolved 10 buffer overflow vulnerabilities in native C components (lemon/lime).
- **Background Persistence:** Bypassed UI dialogs during AutoPilot system restarts to ensure the VPN reconnects successfully while in the background.
- **AutoPilot:** Removed the 5-reset limit to allow indefinite self-healing of connection drops.
- **Update Detection:** Fixed logic to ignore build number differences and only trigger updates on version increments.

### Changed
- **Auto-Restart:** VPN now automatically restarts after an AutoPilot reset to re-trigger the Smart Network Probe for optimal performance in the new location.
