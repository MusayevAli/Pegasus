#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  printf '%s\n' 'Install full Xcode, or set DEVELOPER_DIR to its Contents/Developer directory.' >&2
  exit 1
fi
mkdir -p work
# Pass an installed iPhone Simulator UDID as the first argument, or use the first available iPhone.
simulator_id="${1:-$(xcrun simctl list devices available -j | /usr/bin/python3 -c 'import sys,json; d=json.load(sys.stdin); print(next(x["udid"] for group in d["devices"].values() for x in group if x.get("isAvailable") and x["name"].startswith("iPhone")))')}"
xcodebuild -project ios/PegasusTripFit.xcodeproj -scheme PegasusTripFit \
  -sdk iphonesimulator -destination "id=$simulator_id" \
  -derivedDataPath work/DerivedData CODE_SIGNING_ALLOWED=YES build
if ! xcrun simctl list devices booted | /usr/bin/grep -q "$simulator_id"; then
  xcrun simctl boot "$simulator_id"
fi
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl install "$simulator_id" work/DerivedData/Build/Products/Debug-iphonesimulator/PegasusTripFit.app
xcrun simctl launch "$simulator_id" com.hackathon.PegasusTripFit
printf '%s\n' 'Native app launched. Open Simulator from Xcode → Open Developer Tool → Simulator.'
