#!/bin/bash
set -euo pipefail

# ============================================
#  SentinelCrash — On-Device .deb Builder
#  For use on jailbroken iOS with Theos
#  BarabaDev © 2026
# ============================================

VERSION="1.1.0"
BUNDLE_ID="com.barabadev.sentinelcrash"
APP_NAME="SentinelCrash"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1" >&2; exit 1; }

echo -e ""
echo -e "${BOLD}🛡️  SentinelCrash v${VERSION} — On-Device Build${NC}"
echo -e ""

# ── Method selection ──
if [ "${1:-}" = "--package-only" ] && [ -d "${2:-}" ]; then
    # Package a pre-built .app into .deb
    APP_SRC="$2"
    echo -e "${CYAN}Packaging pre-built app: $APP_SRC${NC}"
elif [ -n "${THEOS:-}" ]; then
    # Build with Theos
    echo -e "${CYAN}Building with Theos...${NC}"
    cd "$ROOT"
    make clean 2>/dev/null || true
    make package FINALPACKAGE=1
    DEB=$(ls -t "$ROOT/packages/"*.deb 2>/dev/null | head -1)
    if [ -n "$DEB" ]; then
        ok "Package ready: $DEB"
        echo ""
        echo -e "Install:  ${CYAN}dpkg -i $DEB${NC}"
        echo -e "Refresh:  ${CYAN}uicache -p /var/jb/Applications/${APP_NAME}.app${NC}"
    else
        fail "No .deb found in packages/"
    fi
    exit 0
else
    echo "Usage:"
    echo "  With Theos:     ./scripts/build-on-device.sh"
    echo "  Package only:   ./scripts/build-on-device.sh --package-only /path/to/SentinelCrash.app"
    echo ""
    echo "Environment:"
    echo "  THEOS=${THEOS:-<not set>}"
    exit 1
fi

# ── Package-only mode ──
BUILD_DIR="$ROOT/build"
PKG_ROOT="$BUILD_DIR/pkg"
DEB_NAME="${APP_NAME}_${VERSION}_iphoneos-arm64.deb"

rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/var/jb/Applications" "$PKG_ROOT/DEBIAN"

# Copy app bundle
cp -R "$APP_SRC" "$PKG_ROOT/var/jb/Applications/${APP_NAME}.app"
ok "App bundle copied"

# Ensure lproj dirs are in the bundle
LANG_COUNT=0
for lproj in "$ROOT/SentinelCrash/"*.lproj; do
    [ -d "$lproj" ] || continue
    DEST="$PKG_ROOT/var/jb/Applications/${APP_NAME}.app/$(basename "$lproj")"
    if [ ! -d "$DEST" ]; then
        cp -R "$lproj" "$DEST"
    fi
    LANG_COUNT=$((LANG_COUNT + 1))
done
ok "$LANG_COUNT language bundles"

# Sign if ldid available
if command -v ldid >/dev/null 2>&1; then
    BIN="$PKG_ROOT/var/jb/Applications/${APP_NAME}.app/${APP_NAME}"
    if [ -f "$BIN" ] && [ -f "$ROOT/SentinelCrash/SentinelCrash.entitlements" ]; then
        ldid -S"$ROOT/SentinelCrash/SentinelCrash.entitlements" "$BIN"
        ok "Signed with entitlements"
    fi
else
    echo -e "  ${RED}⚠${NC} ldid not found — binary not signed"
fi

# DEBIAN files
cp "$ROOT/DEBIAN/control" "$PKG_ROOT/DEBIAN/control"
cp "$ROOT/DEBIAN/postinst" "$PKG_ROOT/DEBIAN/postinst"
cp "$ROOT/DEBIAN/prerm" "$PKG_ROOT/DEBIAN/prerm"
chmod 0755 "$PKG_ROOT/DEBIAN/postinst" "$PKG_ROOT/DEBIAN/prerm"
ok "DEBIAN metadata"

# Build .deb
mkdir -p "$BUILD_DIR"
if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb --root-owner-group -Zxz -b "$PKG_ROOT" "$BUILD_DIR/$DEB_NAME"
elif command -v dpkg >/dev/null 2>&1; then
    dpkg-deb -b "$PKG_ROOT" "$BUILD_DIR/$DEB_NAME"
else
    fail "dpkg-deb not found — install dpkg"
fi

DEB_SIZE=$(du -h "$BUILD_DIR/$DEB_NAME" | cut -f1)
ok "Package: $BUILD_DIR/$DEB_NAME ($DEB_SIZE)"

echo ""
echo -e "${BOLD}${GREEN}✅ Done!${NC}"
echo ""
echo -e "Install:  ${CYAN}dpkg -i $BUILD_DIR/$DEB_NAME${NC}"
echo -e "Refresh:  ${CYAN}uicache -p /var/jb/Applications/${APP_NAME}.app${NC}"
