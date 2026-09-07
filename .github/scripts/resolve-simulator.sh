#!/usr/bin/env bash
#
# Print the UDID of an iOS simulator to run the tests on, creating one if the runner
# has none, and export it as SIM_UDID when running under GitHub Actions.
#
# Why this exists
# ---------------
# `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'` hardcodes a device that
# has to already exist on the runner. Twice now it hasn't: 2026-08-30 and 2026-09-07
# both died with
#
#     xcodebuild: error: Unable to find a device matching the provided destination
#     specifier: { platform:iOS Simulator, OS:latest, name:iPhone 17 Pro }
#
# and on the second the runner listed no concrete simulators at all — only the
# "Any iOS Simulator Device" placeholder. GitHub reimages `macos-26` on its own
# schedule, and the set of preinstalled simulators is not part of any contract we
# can rely on. So resolve a device instead of naming one, and create it if needed.
#
# Prints the inventory either way: when this does fail, the next person should be able
# to see what the runner actually had rather than infer it.

set -euo pipefail

PREFERRED_DEVICE="${PREFERRED_DEVICE:-iPhone 17 Pro}"

echo "Available iOS runtimes:"
xcrun simctl list runtimes ios || true
echo

# An existing booted-or-bootable iPhone is the cheapest answer, and on a developer
# machine it is the one that already has the reference simulators.
udid="$(
  xcrun simctl list devices available --json \
    | PREFERRED="$PREFERRED_DEVICE" python3 -c '
import json, os, sys

preferred = os.environ["PREFERRED"]
runtimes = json.load(sys.stdin)["devices"]

def ios_version(runtime_id):
    # "com.apple.CoreSimulator.SimRuntime.iOS-26-5" -> (26, 5)
    tail = runtime_id.rsplit(".", 1)[-1]
    if not tail.startswith("iOS-"):
        return None
    try:
        return tuple(int(p) for p in tail[4:].split("-"))
    except ValueError:
        return None

candidates = []
for runtime_id, devices in runtimes.items():
    version = ios_version(runtime_id)
    if version is None:
        continue
    for device in devices:
        if not device.get("isAvailable") or "iPhone" not in device.get("name", ""):
            continue
        # Preferred name first, then newest runtime, then newest-sounding iPhone.
        candidates.append((device["name"] == preferred, version, device["name"], device["udid"]))

if candidates:
    print(max(candidates)[3])
'
)"

if [ -n "$udid" ]; then
  echo "Using existing simulator: $udid"
else
  echo "No available iPhone simulator on this runner — creating one."
  echo "Device types:"
  xcrun simctl list devicetypes | grep -i iphone || true

  runtime="$(
    xcrun simctl list runtimes --json | python3 -c '
import json, sys
runtimes = [
    r for r in json.load(sys.stdin)["runtimes"]
    if r.get("isAvailable") and r.get("platform") == "iOS"
]
if not runtimes:
    sys.exit("No available iOS runtime on this runner.")
runtimes.sort(key=lambda r: [int(p) for p in r["version"].split(".")])
print(runtimes[-1]["identifier"])
'
  )"

  device_type="$(
    xcrun simctl list devicetypes --json | PREFERRED="$PREFERRED_DEVICE" python3 -c '
import json, os, re, sys

preferred = os.environ["PREFERRED"]
types = [
    d for d in json.load(sys.stdin)["devicetypes"]
    if d.get("productFamily") == "iPhone"
]
if not types:
    sys.exit("No iPhone device type on this runner.")

def rank(device_type):
    name = device_type["name"]
    generation = re.search(r"iPhone\s+(\d+)", name)
    return (name == preferred, int(generation.group(1)) if generation else 0, "Pro" in name)

print(max(types, key=rank)["identifier"])
'
  )"

  echo "Creating simulator: $device_type on $runtime"
  udid="$(xcrun simctl create "cyclometer-ci" "$device_type" "$runtime")"
fi

xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b || true

echo "SIM_UDID=$udid"
[ -n "${GITHUB_ENV:-}" ] && echo "SIM_UDID=$udid" >> "$GITHUB_ENV"
exit 0
