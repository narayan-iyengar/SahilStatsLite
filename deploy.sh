#!/bin/bash
# deploy.sh — pull, build Release, deploy to iPhone + both Apple Watches
# No USB needed — uses xcrun devicectl over WiFi.
# Usage: bash ~/SahilStats/deploy.sh [--iphone-only | --watch-only | --no-deploy]

set -e

REPO="/Users/narayan/SahilStats/SahilStatsLite/SahilStatsLite"
BUILD_DIR="/tmp/SahilStatsBuild"
IPHONE_DC="Narayans-iPhone.coredevice.local"
WATCH8_DC="Narayans-AppleWatch-8.coredevice.local"
WATCH_ULTRA_DC="Narayans-AppleWatch.coredevice.local"
MODE="${1:-all}"

install_device() {
  local device="$1" app="$2" label="$3"
  echo "==> Installing on $label..."
  for i in 1 2 3; do
    result=$(xcrun devicectl device install app --device "$device" "$app" 2>&1) || true
    if echo "$result" | grep -q "installationURL"; then
      echo "==> $label: done ✅"
      return 0
    fi
    if [ "$i" -lt 3 ]; then
      echo "   Attempt $i failed — retrying in 5s..."
      sleep 5
    else
      echo "   ⚠️  $label: unavailable (wake device and run: bash ~/SahilStats/deploy.sh --watch-only)"
    fi
  done
}

MAC_PASS=$(cat ~/.sahil_deploy_pass 2>/dev/null)
[ -n "$MAC_PASS" ] && security unlock-keychain -p "$MAC_PASS" ~/Library/Keychains/login.keychain-db 2>/dev/null && echo "==> Keychain unlocked"

echo "==> Pulling latest..."
cd "$REPO" && git pull --rebase origin main

echo "==> Building Release..."
xcodebuild \
  -scheme SahilStatsLite \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$BUILD_DIR" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=TTV9QQRD5H \
  CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION=$(git -C "$REPO" rev-list --count HEAD) \
  2>&1 | grep -E 'error:|Build succeeded|Build FAILED' | grep -v SourcePackages | head -20

IPHONE_APP=$(find "$BUILD_DIR" -name "SahilStatsLite.app" -not -path "*/watchos*" -not -path "*Watch*" | head -1)
WATCH_APP="$IPHONE_APP/Watch/SahilStatsLiteWatch Watch App.app"
BUILD_VER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$IPHONE_APP/Info.plist" 2>/dev/null || echo '?')

[ -z "$IPHONE_APP" ] && echo "ERROR: build failed" && exit 1
echo "==> Built v$BUILD_VER (Release)"
[ "$MODE" = "--no-deploy" ] && exit 0

if [ "$MODE" != "--watch-only" ]; then
  install_device "$IPHONE_DC" "$IPHONE_APP" "iPhone"
fi

if [ "$MODE" != "--iphone-only" ] && [ -d "$WATCH_APP" ]; then
  install_device "$WATCH8_DC" "$WATCH_APP" "Watch Series 8"
  echo "$BUILD_VER" > /tmp/_sahil_last_watch_deploy.txt
  install_device "$WATCH_ULTRA_DC" "$WATCH_APP" "Watch Ultra 2"
fi

echo "==> All done! v$BUILD_VER Release on all devices"
