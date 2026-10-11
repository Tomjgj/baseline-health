#!/usr/bin/env bash
# Build Baseline, install it on a connected iPhone and open it. Run from the repo root or ios/:
#
#   TEAM=ABCDE12345 ./ios/run-on-iphone.sh
#
# TEAM      your Apple developer team id (Xcode → Settings → Accounts → your Apple ID → the team's id;
#           a free Apple ID's "Personal Team" works for running on your own phone)
# BUNDLE    optional bundle id, default com.<your mac username>.baseline (must be unique to you)
# DEVICE    optional iPhone UDID, if more than one is connected
#
# The iPhone needs to be unlocked, connected (cable or same Wi-Fi after pairing in Xcode once),
# with Developer Mode on (Settings → Privacy & Security → Developer Mode).
set -euo pipefail

cd "$(dirname "$0")"
: "${TEAM:?Set TEAM to your Apple developer team id, e.g. TEAM=ABCDE12345 ./ios/run-on-iphone.sh}"
BUNDLE="${BUNDLE:-com.$(whoami | tr -cd 'a-zA-Z0-9').baseline}"

command -v xcodegen >/dev/null || { echo "Installing XcodeGen…"; brew install xcodegen; }
xcodegen generate --quiet

if [ -z "${DEVICE:-}" ]; then
  tmp=$(mktemp)
  xcrun devicectl list devices --json-output "$tmp" >/dev/null
  DEVICE=$(python3 - "$tmp" <<'PY'
import json, sys
devs = json.load(open(sys.argv[1])).get("result", {}).get("devices", [])
phones = [d for d in devs if d.get("hardwareProperties", {}).get("platform") == "iOS"
          and d.get("hardwareProperties", {}).get("deviceType") == "iPhone"]
ready = [d for d in phones if d.get("connectionProperties", {}).get("pairingState") == "paired"] or phones
print(ready[0]["hardwareProperties"]["udid"] if ready else "")
PY
)
  rm -f "$tmp"
fi
[ -n "$DEVICE" ] || { echo "No iPhone found. Connect it, unlock it, and trust this Mac."; exit 1; }
echo "Building for $DEVICE as $BUNDLE (team $TEAM)…"
APP=build/Build/Products/Debug-iphoneos/Baseline.app
rm -rf "$APP" # so an old build can't pass for a new one

xcodebuild -project Baseline.xcodeproj -scheme Baseline -configuration Debug \
  -destination "id=$DEVICE" -derivedDataPath build -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" CODE_SIGN_STYLE=Automatic \
  build | grep -E "error:|warning: .*\.swift|BUILD (SUCCEEDED|FAILED)" || true
[ -d "$APP" ] || { echo "Build failed. Open ios/Baseline.xcodeproj in Xcode to see the full error."; exit 1; }

xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE"
cat <<EOF

Baseline is open on your iPhone.
 - Allow the Health categories when asked; the first sync reads the last 180 days.
 - Today should then show your own recovery, sleep and strain instead of the sample person.
 - If iOS says the developer isn't trusted: Settings → General → VPN & Device Management → trust your Apple ID, then open the app again.
 - App logs: Console.app → your iPhone → search "com.example.baseline" (look for "page:" and "sync request").
EOF
