export TEST_RUNNER_STRAVA_LIVE_ACTIVITY_ID=20847838659
export TEST_RUNNER_STRAVA_LIVE_ROUTE_ID=3533551710894699610

open 'https://www.strava.com/oauth/authorize?client_id=300241&response_type=code&redirect_uri=https://acmeapps.xyz/ride/&scope=read,read_all,profile:read_all,activity:read_all&approval_prompt=force'

BASE=https://acmeapps.xyz/ride/api/strava
read -r CODE
echo "Getting refresh token"
RESP=$(curl -s -X POST $BASE/token -H 'Content-Type: application/json' -d "{\"code\":\"$CODE\"}")
echo "$RESP" | jq '{scope, expires_at, athlete: .athlete.id}'
export TEST_RUNNER_STRAVA_LIVE_TOKEN=$(echo "$RESP" | jq -r .access_token)
export TEST_RUNNER_STRAVA_LIVE_ATHLETE_ID=$(echo "$RESP" | jq -r .athlete.id)
export REFRESH=$(echo "$RESP" | jq -r .refresh_token)
echo "Building"
cd Cyclometer
xcodebuild test -project Cyclometer.xcodeproj -scheme Cyclometer \
  -destination "id=$(../scripts/test-simulator.sh)" -collect-test-diagnostics never \
  -only-testing:CyclometerTests/StravaLiveTests 2>&1 | grep -E "strava live:|Test case|error"

