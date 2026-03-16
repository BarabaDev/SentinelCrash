#!/usr/bin/env bash
set -euo pipefail

# ============================================
#  SentinelCrash — Rootless .deb Builder
#  BarabaDev © 2026
# ============================================

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/SentinelCrash.xcarchive"
APP_NAME="SentinelCrash.app"
APP_SRC="$ARCHIVE_PATH/Products/Applications/$APP_NAME"
PKG_ROOT="$BUILD_DIR/package-root"
VERSION="1.1.0"
DEB_NAME="SentinelCrash_${VERSION}_iphoneos-arm64.deb"
START_TIME=$(date +%s)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

step() { echo -e "\n${CYAN}[${1}/6]${NC} ${BOLD}${2}${NC}"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1" >&2; exit 1; }

# ── Tool check ──
require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "Required tool missing: $1"
}

echo -e ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  🛡️  SentinelCrash v${VERSION} — Rootless Build  ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"

# ── Args ──
CLEAN=false
DEPLOY=""
for arg in "$@"; do
  case "$arg" in
    --clean)  CLEAN=true ;;
    --deploy) DEPLOY="auto" ;;
    --deploy=*) DEPLOY="${arg#--deploy=}" ;;
    --help|-h)
      echo ""
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --clean         Clean DerivedData before build"
      echo "  --deploy        Auto-deploy to last used device"
      echo "  --deploy=IP     Deploy to specific device IP"
      echo "  -h, --help      Show this help"
      echo ""
      exit 0
      ;;
  esac
done

# ── Step 1: Validate ──
step 1 "Validating environment..."
require_tool xcodebuild
require_tool ldid
require_tool dpkg-deb
ok "xcodebuild, ldid, dpkg-deb found"

# Check project exists
[ -f "$ROOT/SentinelCrash.xcodeproj/project.pbxproj" ] || fail "Xcode project not found at $ROOT"
ok "Project found"

# Check shared scheme exists (required for xcodebuild -scheme)
SCHEME_FILE="$ROOT/SentinelCrash.xcodeproj/xcshareddata/xcschemes/SentinelCrash.xcscheme"
[ -f "$SCHEME_FILE" ] || fail "Shared scheme missing at $SCHEME_FILE"
ok "Shared scheme found"

# Check workspace data
WORKSPACE_DATA="$ROOT/SentinelCrash.xcodeproj/project.xcworkspace/contents.xcworkspacedata"
[ -f "$WORKSPACE_DATA" ] || fail "Workspace data missing at $WORKSPACE_DATA"
ok "Workspace data OK"

# Check DEBIAN
[ -f "$ROOT/DEBIAN/control" ] || fail "DEBIAN/control missing"
[ -f "$ROOT/DEBIAN/postinst" ] || fail "DEBIAN/postinst missing"
ok "DEBIAN package files OK"

# Check entitlements
[ -f "$ROOT/SentinelCrash/SentinelCrash.entitlements" ] || fail "Entitlements file missing"
ok "Entitlements OK"

# Version consistency
PBXVER=$(grep -o "MARKETING_VERSION = [^;]*" "$ROOT/SentinelCrash.xcodeproj/project.pbxproj" | head -1 | sed 's/MARKETING_VERSION = //' | tr -d ' ')
CTLVER=$(grep "^Version:" "$ROOT/DEBIAN/control" | awk '{print $2}')
if [ "$PBXVER" != "$VERSION" ] || [ "$CTLVER" != "$VERSION" ]; then
  warn "Version mismatch: script=$VERSION pbxproj=$PBXVER control=$CTLVER"
else
  ok "Version $VERSION consistent everywhere"
fi

# Count Swift files vs Sources build phase entries
SWIFT_COUNT=$(find "$ROOT/SentinelCrash" -name "*.swift" | wc -l | tr -d ' ')
# Count PBXBuildFile entries referencing Sources (one per compiled .swift)
BP_COUNT=$(grep -c "in Sources" "$ROOT/SentinelCrash.xcodeproj/project.pbxproj" || echo 0)
if [ "$SWIFT_COUNT" != "$BP_COUNT" ]; then
  warn "Swift files: $SWIFT_COUNT disk vs $BP_COUNT in Sources build phase"
else
  ok "$SWIFT_COUNT Swift files registered"
fi

# Count languages
LANG_COUNT=$(find "$ROOT/SentinelCrash" -name "*.lproj" -type d | wc -l | tr -d ' ')
ok "$LANG_COUNT languages"

# ── Step 2: Clean ──
step 2 "Preparing build directory..."
mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$PKG_ROOT"
ok "Build dir clean"

if $CLEAN; then
  echo -e "  ${YELLOW}Cleaning DerivedData...${NC}"
  xcodebuild -project "$ROOT/SentinelCrash.xcodeproj" -scheme SentinelCrash clean 2>/dev/null || true
  ok "DerivedData cleaned"
fi

# ── Step 3: Build ──
step 3 "Building archive (Release, arm64)..."
BUILD_LOG="$BUILD_DIR/build.log"

xcodebuild \
  -project "$ROOT/SentinelCrash.xcodeproj" \
  -scheme SentinelCrash \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -sdk iphoneos \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  archive 2>&1 | tee "$BUILD_LOG" | grep -E "error:|warning:.*error|ARCHIVE|SUCCEEDED|FAILED" | head -30

# Check result
if grep -q "ARCHIVE SUCCEEDED" "$BUILD_LOG"; then
  ok "Archive succeeded"
elif grep -q "ARCHIVE FAILED" "$BUILD_LOG"; then
  echo ""
  echo -e "${RED}${BOLD}BUILD FAILED — Errors:${NC}"
  grep "error:" "$BUILD_LOG" | head -15
  echo ""
  echo -e "Full log: ${CYAN}$BUILD_LOG${NC}"
  fail "xcodebuild archive failed"
fi

[ -d "$APP_SRC" ] || fail "App bundle missing at $APP_SRC"

# Show binary info
APP_BIN="$APP_SRC/SentinelCrash"
BIN_SIZE=$(du -h "$APP_BIN" | cut -f1)
ok "Binary: $BIN_SIZE"

# ── Step 4: Sign ──
step 4 "Signing with ldid..."
ldid -S"$ROOT/SentinelCrash/SentinelCrash.entitlements" "$APP_BIN"
ok "Signed with entitlements"

# ── Step 5: Package ──
step 5 "Assembling .deb package..."
mkdir -p "$PKG_ROOT/var/jb/Applications" "$PKG_ROOT/DEBIAN"
cp -R "$APP_SRC" "$PKG_ROOT/var/jb/Applications/"
cp "$ROOT/DEBIAN/control" "$PKG_ROOT/DEBIAN/control"
cp "$ROOT/DEBIAN/postinst" "$PKG_ROOT/DEBIAN/postinst"
cp "$ROOT/DEBIAN/prerm" "$PKG_ROOT/DEBIAN/prerm"
chmod 0755 "$PKG_ROOT/DEBIAN/postinst" "$PKG_ROOT/DEBIAN/prerm"

# Verify .lproj dirs are in the app bundle
BUNDLE_LANGS=$(find "$PKG_ROOT/var/jb/Applications/$APP_NAME" -name "*.lproj" -type d | wc -l | tr -d ' ')
ok "$BUNDLE_LANGS language bundles included"

dpkg-deb --root-owner-group -b "$PKG_ROOT" "$BUILD_DIR/$DEB_NAME"
ok "Package built"

# ── Step 6: Summary ──
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
DEB_SIZE=$(du -h "$BUILD_DIR/$DEB_NAME" | cut -f1)

step 6 "Done!"
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  ${GREEN}✅  BUILD COMPLETE${NC}${BOLD}                        ║${NC}"
echo -e "${BOLD}╠══════════════════════════════════════════╣${NC}"
echo -e "${BOLD}║${NC}  Package:  ${CYAN}$DEB_NAME${NC}"
echo -e "${BOLD}║${NC}  Size:     ${GREEN}$DEB_SIZE${NC}"
echo -e "${BOLD}║${NC}  Time:     ${YELLOW}${ELAPSED}s${NC}"
echo -e "${BOLD}║${NC}  Swift:    $SWIFT_COUNT files"
echo -e "${BOLD}║${NC}  Langs:    $LANG_COUNT"
echo -e "${BOLD}║${NC}  Version:  $VERSION"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"

# ── Auto-deploy ──
if [ -n "$DEPLOY" ]; then
  echo ""
  if [ "$DEPLOY" = "auto" ]; then
    # Try last known IP from cache
    CACHE="$BUILD_DIR/.last_device_ip"
    if [ -f "$CACHE" ]; then
      DEPLOY=$(cat "$CACHE")
      echo -e "Using cached device IP: ${CYAN}$DEPLOY${NC}"
    else
      echo -e "${YELLOW}No cached device IP. Use: $0 --deploy=192.168.x.x${NC}"
      exit 0
    fi
  fi

  echo -e "${CYAN}Deploying to $DEPLOY...${NC}"
  echo "$DEPLOY" > "$BUILD_DIR/.last_device_ip"

  scp "$BUILD_DIR/$DEB_NAME" "root@${DEPLOY}:/tmp/" && ok "Transferred" || fail "SCP failed"
  ssh "root@${DEPLOY}" "dpkg -i /tmp/$DEB_NAME && uicache -p /var/jb/Applications/SentinelCrash.app" && ok "Installed + cache refreshed" || fail "Install failed"

  echo ""
  echo -e "${GREEN}${BOLD}🛡️  SentinelCrash v${VERSION} deployed to $DEPLOY${NC}"
else
  echo ""
  echo "Install manually:"
  echo -e "  ${CYAN}scp${NC} $BUILD_DIR/$DEB_NAME ${CYAN}root@<device-ip>:/tmp/${NC}"
  echo -e "  ${CYAN}ssh root@<device-ip>${NC} dpkg -i /tmp/$DEB_NAME"
  echo -e "  ${CYAN}ssh root@<device-ip>${NC} uicache -p /var/jb/Applications/SentinelCrash.app"
fi
