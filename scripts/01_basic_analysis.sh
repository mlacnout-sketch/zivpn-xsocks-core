#!/bin/bash
# File: scripts/01_basic_analysis.sh

# This script performs basic static analysis on the target binaries.
# It assumes tools like readelf, strings, and file are available.

BINARY_UZ="android/app/src/main/jniLibs/arm64-v8a/libuz.so"
BINARY_LOAD="android/app/src/main/jniLibs/arm64-v8a/libload.so"
REPORT_DIR="analysis/reports"

mkdir -p "$REPORT_DIR"

echo "╔══════════════════════════════════════════════════════╗"
echo "║  BASIC BINARY ANALYSIS                               ║"
echo "╚══════════════════════════════════════════════════════╝"

# ═══ FILE TYPE & ARCHITECTURE ═══
echo -e "\n[1] File Type Analysis:"
if [ -f "$BINARY_UZ" ]; then
    file "$BINARY_UZ"
else
    echo "libuz.so not found at $BINARY_UZ"
fi

if [ -f "$BINARY_LOAD" ]; then
    file "$BINARY_LOAD"
else
    echo "libload.so not found at $BINARY_LOAD"
fi

# ═══ READELF - ELF HEADER INFO ═══
echo -e "\n[2] ELF Header Information:"
if [ -f "$BINARY_UZ" ]; then
    readelf -h "$BINARY_UZ" > "$REPORT_DIR/libuz_header.txt"
    echo "Saved to $REPORT_DIR/libuz_header.txt"
fi
if [ -f "$BINARY_LOAD" ]; then
    readelf -h "$BINARY_LOAD" > "$REPORT_DIR/libload_header.txt"
    echo "Saved to $REPORT_DIR/libload_header.txt"
fi

# ═══ SECTION HEADERS ═══
echo -e "\n[3] Section Headers:"
if [ -f "$BINARY_UZ" ]; then
    readelf -S "$BINARY_UZ" > "$REPORT_DIR/libuz_sections.txt"
    echo "Saved to $REPORT_DIR/libuz_sections.txt"
fi

# ═══ DEPENDENCIES ═══
echo -e "\n[6] Library Dependencies:"
if [ -f "$BINARY_UZ" ]; then
    readelf -d "$BINARY_UZ" | grep NEEDED
fi

# ═══ STRINGS ANALYSIS ═══
echo -e "\n[7] Extracting Readable Strings:"
if [ -f "$BINARY_UZ" ]; then
    strings -n 10 "$BINARY_UZ" | head -n 20 > "$REPORT_DIR/libuz_strings_sample.txt"
    echo "Saved sample to $REPORT_DIR/libuz_strings_sample.txt"
fi

echo -e "\n✓ Basic analysis complete. Results in $REPORT_DIR/"
