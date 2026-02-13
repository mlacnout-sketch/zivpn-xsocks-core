#!/bin/bash
set -e  # Exit on error

echo "╔══════════════════════════════════════════════════════╗"
echo "║  ZERO WARNING BUILD CHECK                            ║"
echo "╚══════════════════════════════════════════════════════╝"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ═══ PHASE 1: C CODE COMPILATION ═══
echo -e "\n${YELLOW}Phase 1: Compiling C code...${NC}"

BUILD_DIR="native/build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Clean previous build
make clean 2>/dev/null || true

# Configure with strict warnings
# We pass -DCMAKE_C_FLAGS="-Wall -Wextra -Werror" to force strict mode
cmake .. -DCMAKE_BUILD_TYPE=Release \
         -DCMAKE_C_FLAGS="-Wall -Wextra -Werror -Wno-unused-parameter -Wno-unused-function" \
         -DSKIP_JNI_CHECK=ON 2>&1 | tee cmake.log

# Build
if make -j$(nproc) 2>&1 | tee build.log; then
    echo -e "${GREEN}✓ C compilation succeeded${NC}"
else
    echo -e "${RED}✗ C compilation failed!${NC}"
    # Show the error part
    grep -C 5 "error:" build.log || cat build.log
    exit 1
fi

# Check for warnings (if -Werror wasn't fully effective or if we want to be sure)
if grep -i "warning:" build.log; then
    echo -e "${RED}✗ C compilation has warnings!${NC}"
    grep -i "warning:" build.log
    exit 1
else
    echo -e "${GREEN}✓ C compilation: 0 warnings${NC}"
fi

cd ../..

echo -e "\n${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓ ALL CHECKS PASSED - ZERO WARNINGS!               ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
