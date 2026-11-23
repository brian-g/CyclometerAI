#!/usr/bin/env bash
#
# Print the UDID of the simulator the tests run on: "Cyclometer Tests", an iPhone 17 Pro on
# iOS 27.0, erased first so every setting is iOS's default. Creates it if it doesn't exist.
#
#   xcodebuild test -project Cyclometer.xcodeproj -scheme Cyclometer \
#     -destination "id=$(../scripts/test-simulator.sh)" -only-testing:CyclometerTests
#
# Why this exists
# ---------------
# Snapshot references are pixels, and a simulator's own settings change the pixels. On
# 2026-11-22 the everyday "iPhone 17 Pro" had its text size set to Medium in Device Hub, and
# 292 correct snapshots failed (#648). A fresh device passed them all. The tests now run on a
# device of their own, erased each run, so nothing set by hand on a simulator reaches them:
# not text size, Bold Text, contrast, language, region or 24-hour time. The snapshots also pin
# text size, Bold Text and contrast themselves (`UITraitCollection.snapshot`), for runs from
# Xcode against any simulator.
#
# This device is for the tests only. Don't customise it in Device Hub; it's erased anyway.
#
# iOS 27.0 is the runtime the references are recorded on (.claude/rules/testing.md). There is
# no fallback: 27.2 anti-aliases arc edges differently (see .github/scripts/resolve-simulator.sh),
# so a run on another runtime would fail snapshots for a reason that isn't in the code. CI
# resolves its own simulator with that script, on a fresh runner.
#
# Erasing also drops the app's location decision, and the map widget's layout spins forever
# without one: MapWidgetAccessibilityTests hang, and their spin times out tests beside them. So
# after the erase this installs the newest Cyclometer.app build and grants it location; test
# clones inherit the grant. The grant is lost if the app isn't installed, so build first (the
# build command in CLAUDE.md); with no build to install, this stops rather than hand back a
# device the suite would hang on. APP=/path/to/Cyclometer.app picks the build.
#
# Only this device is ever shut down or erased. Never `simctl shutdown all`: it takes down
# simulators other sessions are using.

set -euo pipefail

NAME="Cyclometer Tests"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-0"

udid="$(
  xcrun simctl list devices --json | NAME="$NAME" RUNTIME="$RUNTIME" python3 -c '
import json, os, sys
devices = json.load(sys.stdin)["devices"].get(os.environ["RUNTIME"], [])
matches = [d["udid"] for d in devices if d["name"] == os.environ["NAME"] and d.get("isAvailable")]
print(matches[0] if matches else "")
'
)"

if [ -z "$udid" ]; then
  if ! xcrun simctl list runtimes --json | grep -q "\"identifier\" : \"$RUNTIME\""; then
    echo "error: the iOS 27.0 simulator runtime isn't installed; the snapshot references need it." >&2
    exit 1
  fi
  udid="$(xcrun simctl create "$NAME" "$DEVICE_TYPE" "$RUNTIME")"
  echo "Created \"$NAME\" ($udid)." >&2
fi

app="${APP:-$(
  find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 5 -type d \
    -path "*/Cyclometer-*/Build/Products/Debug-iphonesimulator/Cyclometer.app" -print0 2>/dev/null \
    | xargs -0 stat -f "%m %N" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
)}"
if [ -z "$app" ] || [ ! -d "$app" ]; then
  echo "error: no Cyclometer.app build to install; run the build command in CLAUDE.md first." >&2
  exit 1
fi
bundle_id="$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$app/Info.plist")"

# Erase needs it shut down. Shutting down a device that already is fails harmlessly.
xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
xcrun simctl erase "$udid"

xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl install "$udid" "$app"
xcrun simctl privacy "$udid" grant location "$bundle_id"
clients="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Caches/locationd/clients.plist"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  plutil -p "$clients" 2>/dev/null | grep -q "$bundle_id" && break
  sleep 1
done
if ! plutil -p "$clients" 2>/dev/null | grep -q "$bundle_id"; then
  echo "error: the location grant for $bundle_id didn't register on \"$NAME\"." >&2
  exit 1
fi
xcrun simctl shutdown "$udid"

echo "$udid"
