#!/bin/bash
# deploy.sh — pull, build Release, deploy to iPhone + both Apple Watches
# Uses xcodebuild for iPhone (reliable). Watch companion is pushed automatically
# via iPhone when the Watch is the active paired Watch on the iPhone.
# For Watch 8: switch to it in the Watch app on iPhone, then run this script.
# For Watch Ultra: switch to it, then run again.
# Usage: bash ~/SahilStats/deploy.sh [--iphone-only | --no-deploy]

set -e

REPO="/Users/narayan/SahilStats/SahilStatsLite/SahilStatsLite"
IPHONE_UDID="E52AFF08-9E71-52C0-8608-A9A529C5205C"
MODE="${1:-all}"

MAC_PASS=$(cat ~/.sahil_deploy_pass 2>/dev/null)
[ -n "$MAC_PASS" ] && security unlock-keychain -p "$MAC_PASS" ~/Library/Keychains/login.keychain-db 2>/dev/null && echo "==> Keychain unlocked"

echo "==> Pulling latest..."
cd "$REPO" && git pull --rebase origin main

BUILD_VER=$(git -C "$REPO" rev-list --count HEAD)
echo "==> Building + deploying v$BUILD_VER (Release)..."

[ "$MODE" = "--no-deploy" ] && xcodebuild \
  -scheme SahilStatsLite -configuration Release \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=TTV9QQRD5H \
  CODE_SIGN_STYLE=Automatic CURRENT_PROJECT_VERSION="$BUILD_VER" \
  2>&1 | grep -E 'error:|Build succeeded|Build FAILED' | grep -v SourcePackages | head -20 && exit 0

# Build AND install on iPhone in one shot.
# The Watch companion is automatically pushed to whichever Watch is currently
# active/paired on the iPhone — no separate Watch UDID needed.
result=$(xcodebuild \
  -scheme SahilStatsLite \
  -configuration Release \
  -destination "platform=iOS,id=$IPHONE_UDID" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=TTV9QQRD5H \
  CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION="$BUILD_VER" \
  2>&1) || true

if echo "$result" | grep -q "Build succeeded"; then
  echo "$result" | grep -E 'error:' | grep -v SourcePackages | head -5
  echo "==> iPhone + active Watch: done ✅ (v$BUILD_VER)"
else
  echo "$result" | grep -E 'error:|warning.*provisioning' | grep -v SourcePackages | head -10
  echo "==> ⚠️  Deploy failed — check errors above"
  exit 1
fi

echo "==> All done! v$BUILD_VER"
echo "    To deploy to the OTHER Watch: switch active Watch in the Watch app, then re-run."
