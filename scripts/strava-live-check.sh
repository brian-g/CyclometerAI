#!/usr/bin/env bash
#
# Run StravaLiveTests against Strava (#627): authorize in the browser, paste the code, and the
# script exchanges it through the token service, runs the tests, and revokes the token at the end.
# No token is printed or stored.
#
# Usage: scripts/strava-live-check.sh   (from any directory)
#
# The activity and route default to a public ride and route on the maintainer's Strava account, published on
# purpose. To check others: STRAVA_LIVE_ACTIVITY_ID=… STRAVA_LIVE_ROUTE_ID=… scripts/strava-live-check.sh

set -o pipefail
cd "$(dirname "$0")/.." || exit 1

export TEST_RUNNER_STRAVA_LIVE_ACTIVITY_ID="${STRAVA_LIVE_ACTIVITY_ID:-20847838659}"
export TEST_RUNNER_STRAVA_LIVE_ROUTE_ID="${STRAVA_LIVE_ROUTE_ID:-3533551710894699610}"

open 'https://www.strava.com/oauth/authorize?client_id=300241&response_type=code&redirect_uri=https://acmeapps.xyz/ride/&scope=read,read_all,profile:read_all,activity:read_all&approval_prompt=force'

BASE=https://acmeapps.xyz/ride/api/strava
echo "Paste the code from the address bar, then press Return:"
read -r CODE
echo "Getting tokens"
RESP=$(curl -s -X POST $BASE/token -H 'Content-Type: application/json' -d "{\"code\":\"$CODE\"}")
if [ "$(echo "$RESP" | jq -r '.access_token // empty' 2>/dev/null)" = "" ]; then
  echo "The code exchange failed (a code works once, and only briefly). Strava answered:"
  echo "$RESP" | jq . 2>/dev/null || echo "$RESP" | head -c 300
  exit 1
fi
echo "$RESP" | jq '{scope, expires_at, athlete: .athlete.id}'
export TEST_RUNNER_STRAVA_LIVE_TOKEN=$(echo "$RESP" | jq -r .access_token)
export TEST_RUNNER_STRAVA_LIVE_ATHLETE_ID=$(echo "$RESP" | jq -r .athlete.id)
REFRESH=$(echo "$RESP" | jq -r .refresh_token)

# Revoke however the script ends, Control-C included. Revoking the refresh token revokes both.
revoke() {
  curl -s -o /dev/null -w "Revoked the token: %{http_code}\n" -X POST $BASE/revoke \
    -H 'Content-Type: application/json' -d "{\"token\":\"$REFRESH\"}"
}
trap revoke EXIT

echo "Building"
cd Cyclometer || exit 1
xcodebuild test -project Cyclometer.xcodeproj -scheme Cyclometer \
  -destination "id=$(../scripts/test-simulator.sh)" -collect-test-diagnostics never \
  -only-testing:CyclometerTests/StravaLiveTests 2>&1 | grep -E "strava live:|Test case|error|failed"
