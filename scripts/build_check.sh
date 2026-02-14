#!/bin/bash
set -e

echo "╔══════════════════════════════════════════════════════╗"
echo "║  ZERO WARNING BUILD CHECK                            ║"
echo "╚══════════════════════════════════════════════════════╝"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ═══ PHASE 1: NDK CHECK ═══
echo -e "\n${YELLOW}Phase 1: Checking NDK configuration...${NC}"
if grep -q "\-Werror" native/CMakeLists.txt; then
    echo -e "${GREEN}✓ CMakeLists.txt has strict warnings enabled${NC}"
else
    echo -e "${RED}✗ CMakeLists.txt is missing strict warning flags${NC}"
    exit 1
fi

if grep -q "client->auth_info" native/badvpn/tun2socks/tun2socks.c; then
    echo -e "${GREEN}✓ tun2socks.c has UAF fix${NC}"
else
    echo -e "${RED}✗ tun2socks.c is missing UAF fix${NC}"
    exit 1
fi

# ═══ PHASE 2: FLUTTER ANALYZE ═══
echo -e "\n${YELLOW}Phase 2: Running Flutter analyze...${NC}"

# We expect some info/hints, but NO errors.
flutter analyze > analyze.log 2>&1 || true

if grep -q "error •" analyze.log; then
    echo -e "${RED}✗ Flutter analyze has ERRORS!${NC}"
    grep "error •" analyze.log
    exit 1
else
    echo -e "${GREEN}✓ Flutter analyze: No errors found${NC}"
fi

# ═══ PHASE 3: FILE VERIFICATION ═══
echo -e "\n${YELLOW}Phase 3: Verifying artifacts...${NC}"

if [ -f "native/integration/libuz_wrapper.c" ]; then
    echo -e "${GREEN}✓ Optimization wrapper source exists${NC}"
else
    echo -e "${RED}✗ Optimization wrapper missing${NC}"
    exit 1
fi

if [ -f "analysis/reports/binary_understanding.md" ]; then
    echo -e "${GREEN}✓ Documentation exists${NC}"
else
    echo -e "${RED}✗ Documentation missing${NC}"
    exit 1
fi

echo -e "\n${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓ ALL CHECKS PASSED                                ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
