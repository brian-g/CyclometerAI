#!/usr/bin/env bash
#
# Run CyclometerTests repeatedly under CPU contention, and report every failure.
#
# Why this exists
# ---------------
# The suite's async races do not show up on an idle machine. Six consecutive local
# runs were green while CI failed on the same commit; the difference was load, not
# code. A test that awaits a state stream and then reads a value the client writes
# *after* publishing that state passes whenever the client's task happens to be
# scheduled first — which, unloaded, is essentially always.
#
# So "it passes locally" proves nothing about these tests. This is what proves
# something: contend for the cores, run it N times, and see what falls out.
#
# Usage:  scripts/stress-tests.sh [runs] [load-processes]
# Default: 10 runs, half a spinner per core — enough contention to surface the races
# without starving the simulator, which needs cores of its own to be worth testing.
#
# Note the whole suite is ~8 seconds of execution, so 10 runs is minutes, not hours.
# Nearly all the wall-clock below is the incremental build and simulator boot.

set -uo pipefail

RUNS="${1:-10}"
LOAD="${2:-$(( $(sysctl -n hw.ncpu) / 2 ))}"

cd "$(dirname "$0")/.."/Cyclometer || exit 1

OUT="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; xcrun simctl shutdown all >/dev/null 2>&1; rm -rf "$OUT"' EXIT

echo "Stressing CyclometerTests: $RUNS runs, $LOAD load processes."
echo "Logs: $OUT"
echo

for _ in $(seq 1 "$LOAD"); do
  ( while :; do :; done ) &
done

failures=0
for i in $(seq 1 "$RUNS"); do
  log="$OUT/run$i.log"
  # -parallel-testing-enabled NO for the same reason CI uses it: the cloned-destination
  # reporter prints a bare test name and no assertion text, which is useless here.
  xcodebuild test \
    -project Cyclometer.xcodeproj \
    -scheme Cyclometer \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -skipMacroValidation \
    -parallel-testing-enabled NO \
    -only-testing:CyclometerTests \
    > "$log" 2>&1
  status=$?

  # Each run leaves a booted simulator and its full daemon set behind, and they
  # accumulate: an earlier 10-run pass ended with 221 simulator processes and was
  # killed by the OS for memory pressure before it finished. Shutting down between
  # runs also makes every run start from the same state, which is the point.
  xcrun simctl shutdown all >/dev/null 2>&1

  if [ $status -eq 0 ]; then
    printf 'run %2d/%d  ok\n' "$i" "$RUNS"
  else
    failures=$((failures + 1))
    printf 'run %2d/%d  FAILED\n' "$i" "$RUNS"
    grep -aE '^✘ Test .* recorded an issue' "$log" | sed 's/^/    /'
    # A failure with no recorded issue is the build or the simulator, not a test.
    grep -aqE '^✘ Test .* recorded an issue' "$log" \
      || sed 's/^/    /' <<< "$(grep -aE 'error:|Simulator device failed' "$log" | head -3)"
  fi
done

echo
if [ "$failures" -eq 0 ]; then
  echo "All $RUNS runs passed under load."
else
  echo "$failures of $RUNS runs failed. Full logs in $OUT (not deleted on failure)."
  trap 'kill $(jobs -p) 2>/dev/null' EXIT
fi
exit $((failures > 0))
