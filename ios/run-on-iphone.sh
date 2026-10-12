#!/usr/bin/env bash
# Build Baseline, install it on a connected iPhone and open it. Run from the repo root or ios/:
#
#   ./ios/run-on-iphone.sh
#
# TEAM      optional Apple developer team id; found automatically from the Apple Development certificate
#           Xcode creates when you sign in (a free Apple ID's "Personal Team" works for your own phone)
# BUNDLE    optional bundle id, default com.<your mac username>.baseline (must be unique to you); the watch app gets BUNDLE.watchkitapp
# DEVICE    optional iPhone UDID, if more than one is connected
#
# The iPhone needs to be unlocked, connected (cable or same Wi-Fi after pairing in Xcode once),
# with Developer Mode on (Settings → Privacy & Security → Developer Mode).
#
# It builds the full app (widgets, Live Activity, watch complications). Those need an App Group, which a free Apple ID's
# Personal Team may not allow; if signing fails for that reason, it builds Baseline Lite instead (the same app without them).
set -euo pipefail

cd "$(dirname "$0")"
if [ -z "${TEAM:-}" ]; then
  # the team id is the OU of the Apple Development certificate Xcode creates when you sign in
  TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -subject -nameopt multiline 2>/dev/null | awk -F' = ' '/organizationalUnitName/ {print $2; exit}' || true)
fi
if [ -z "$TEAM" ]; then
  echo "Couldn't find your Apple developer team. In Xcode: Settings → Accounts → + → Apple ID and sign in,"
  echo "then select your team → Manage Certificates… → + → Apple Development → Done. Then run this again."
  exit 1
fi
BUNDLE="${BUNDLE:-com.$(whoami | tr -cd 'a-zA-Z0-9').baseline}"

command -v xcodegen >/dev/null || { echo "Installing XcodeGen…"; brew install xcodegen; }
xcodegen generate --quiet
xcodegen generate --quiet --spec project-lite.yml

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

mkdir -p build
# builds one project; succeeds only if xcodebuild says so (a half-signed .app can be left behind on failure)
run_build() {
  rm -rf "$APP"
  xcodebuild -project "$1" -scheme Baseline -configuration Debug \
    -destination "id=$DEVICE" -derivedDataPath build -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" BASE_BUNDLE_ID="$BUNDLE" CODE_SIGN_STYLE=Automatic \
    build > build/xcodebuild.log 2>&1 || true
  grep -E "error:|warning: .*\.swift|BUILD (SUCCEEDED|FAILED)" build/xcodebuild.log || true
  grep -q "BUILD SUCCEEDED" build/xcodebuild.log && [ -d "$APP" ]
}
PROJECT=Baseline.xcodeproj
if ! run_build "$PROJECT" && grep -qiE "app groups|application-groups|personal development team|personal team" build/xcodebuild.log; then
  echo
  echo "Your Apple ID's Personal Team can't sign the widgets: they need an App Group, which free Apple IDs may not get."
  echo "Building Baseline Lite instead. It's the same app and watch app, without the widgets, the workout Live Activity"
  echo "and the watch complications."
  echo
  PROJECT="Baseline Lite.xcodeproj"
  run_build "$PROJECT" || true
fi
if ! grep -q "BUILD SUCCEEDED" build/xcodebuild.log || [ ! -d "$APP" ]; then
  echo "Build failed. Open \"ios/$PROJECT\" in Xcode to see the full error (the full log is ios/build/xcodebuild.log)."
  exit 1
fi

xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE"
cat <<EOF

Baseline is open on your iPhone.
 - Allow the Health categories when asked; the first sync reads the last 180 days.
 - Today should then show your own recovery, sleep and strain instead of the sample person.
 - If iOS says the developer isn't trusted: Settings → General → VPN & Device Management → trust your Apple ID, then open the app again.
 - The watch app installs with it if your Apple Watch is paired: open the Watch app on your iPhone → Baseline → Install, if it doesn't appear on its own.
 - App logs: Console.app → your iPhone → search "com.example.baseline" (look for "page:" and "sync request").
EOF
