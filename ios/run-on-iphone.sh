#!/usr/bin/env bash
# Build Baseline, install it on a connected iPhone and open it. Run from the repo root or ios/:
#
#   ./ios/run-on-iphone.sh
#
# TEAM      optional Apple developer team id; found automatically from the Apple Development certificate
#           Xcode creates when you sign in (a free Apple ID's "Personal Team" works for your own phone)
# BUNDLE    optional bundle id, default com.<your mac username>.baseline (must be unique to you); the watch app gets BUNDLE.watchkitapp
# DEVICE    optional iPhone UDID, if more than one is connected
# WATCH     optional Apple Watch UDID; found automatically when Xcode can see the watch paired with the iPhone
#
# A watch app you build yourself installs only on a watch your signing profile lists, and the watch needs Developer Mode.
# So when Xcode can see your Apple Watch, the script builds the watch app for it first (which adds the watch to your
# profile) and installs it on the watch directly, instead of leaving it to the Watch app on the iPhone.
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

# the Apple Watch, when Xcode can see it (paired with the iPhone, Developer Mode on, unlocked)
if [ -z "${WATCH:-}" ]; then
  tmp=$(mktemp)
  xcrun devicectl list devices --json-output "$tmp" >/dev/null 2>&1 || true
  WATCH=$(python3 - "$tmp" <<'PY'
import json, sys
try: devs = json.load(open(sys.argv[1])).get("result", {}).get("devices", [])
except Exception: devs = []
w = [d for d in devs if d.get("hardwareProperties", {}).get("platform") == "watchOS"]
ready = [d for d in w if d.get("connectionProperties", {}).get("pairingState") == "paired"] or w
print(ready[0]["hardwareProperties"]["udid"] if ready else "")
PY
)
  rm -f "$tmp"
fi
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
WATCH_APP=build/Build/Products/Debug-watchos/BaselineWatch.app
# builds the watch app for the watch itself, so Xcode adds the watch to your signing profile
watch_build() {
  rm -rf "$WATCH_APP"
  xcodebuild -project "$1" -scheme BaselineWatch -configuration Debug \
    -destination "id=$WATCH" -derivedDataPath build -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" BASE_BUNDLE_ID="$BUNDLE" CODE_SIGN_STYLE=Automatic \
    build > build/watchbuild.log 2>&1 || true
  grep -E "error:|BUILD (SUCCEEDED|FAILED)" build/watchbuild.log || true
  grep -q "BUILD SUCCEEDED" build/watchbuild.log && [ -d "$WATCH_APP" ]
}
PROJECT=Baseline.xcodeproj
if [ -n "$WATCH" ]; then
  echo "Apple Watch found ($WATCH): building the watch app for it first…"
  if ! watch_build "$PROJECT" && grep -qiE "app groups|application-groups|personal development team|personal team" build/watchbuild.log; then
    PROJECT="Baseline Lite.xcodeproj"
    watch_build "$PROJECT" || true
  fi
fi
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
WATCH_NOTE=" - The watch app: Xcode couldn't see your Apple Watch, so it wasn't added to your signing profile and the Watch app on the
   iPhone can't install it yet. See \"Installing the watch app\" in ios/README.md (Developer Mode on the watch), then run this again."
if [ -n "$WATCH" ]; then
  # the iPhone build replaced the watch build's folder, so build it for the watch once more (quick now) and install it directly
  if watch_build "$PROJECT" && xcrun devicectl device install app --device "$WATCH" "$WATCH_APP"; then
    WATCH_NOTE=" - The watch app is installed on your Apple Watch: find Baseline in the app list (press the Digital Crown)."
  else
    WATCH_NOTE=" - The watch app didn't install on the watch (the log is ios/build/watchbuild.log). Check Developer Mode on the
   watch (Settings → Privacy & Security), keep it unlocked and on the charger next to the iPhone, and run this again."
  fi
fi
cat <<EOF

Baseline is open on your iPhone.
 - Allow the Health categories when asked; the first sync reads the last 180 days.
 - Today should then show your own recovery, sleep and strain instead of the sample person.
 - If iOS says the developer isn't trusted: Settings → General → VPN & Device Management → trust your Apple ID, then open the app again.
$WATCH_NOTE
 - App logs: Console.app → your iPhone → search "com.example.baseline" (look for "page:" and "sync request").
EOF
