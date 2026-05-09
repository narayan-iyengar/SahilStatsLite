#!/bin/bash
# deploy.sh — pull, build Release, deploy to iPhone + both Apple Watches
# Uses xcodebuild directly for all installs (more reliable than devicectl over WiFi).
# Usage: bash ~/SahilStats/deploy.sh [--iphone-only | --watch-only | --no-deploy]

set -e

REPO="/Users/narayan/SahilStats/SahilStatsLite/SahilStatsLite"
IPHONE_UDID="E52AFF08-9E71-52C0-8608-A9A529C5205C"
WATCH8_UDID="1F6B54B5-D413-548A-A90C-351867F22E2C"
WATCH_ULTRA_UDID="4532002B-DBB1-5C2B-B91A-7E51BB05486A"
MODE="${1:-all}"

xcode_install() {
  local udid="$1" platform="$2" label="$3"
  echo "==> Installing on $label..."
  result=$(xcodebuild \
    -scheme SahilStatsLite \
    -configuration Release \
    -destination "platform=$platform,id=$udid" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM=TTV9QQRD5H \
    CODE_SIGN_STYLE=Automatic \
    CURRENT_PROJECT_VERSION=$(git -C "$REPO" rev-list --count HEAD) \
    2>&1) || true
  if echo "$result" | grep -q "Build succeeded"; then
    echo "==> $label: done ✅"
    return 0
  else
    echo "$result" | grep -E 'error:|warning.*provisioning' | grep -v SourcePackages | head -5
    echo "   ⚠️  $label: install failed"
    return 1
  fi
}

MAC_PASS=$(cat ~/.sahil_deploy_pass 2>/dev/null)
[ -n "$MAC_PASS" ] && security unlock-keychain -p "$MAC_PASS" ~/Library/Keychains/login.keychain-db 2>/dev/null && echo "==> Keychain unlocked"

echo "==> Pulling latest..."
cd "$REPO" && git pull --rebase origin main

# Get build version from git
BUILD_VER=$(git -C "$REPO" rev-list --count HEAD)
echo "==> Building v$BUILD_VER (Release)..."

# Build once for iOS (covers iPhone + Watch extension in one shot)
xcodebuild \
  -scheme SahilStatsLite \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=TTV9QQRD5H \
  CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION="$BUILD_VER" \
  2>&1 | grep -E 'error:|Build succeeded|Build FAILED' | grep -v SourcePackages | head -20

[ "$MODE" = "--no-deploy" ] && exit 0

if [ "$MODE" != "--watch-only" ]; then
  xcode_install "$IPHONE_UDID" "iOS" "iPhone"
fi

if [ "$MODE" != "--iphone-only" ]; then
  xcode_install "$WATCH8_UDID" "watchOS" "Watch Series 8" || true
  xcode_install "$WATCH_ULTRA_UDID" "watchOS" "Watch Ultra 2" || true
fi

echo "==> All done! v$BUILD_VER Release on all devices"
