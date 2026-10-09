#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work/profile-model-tests
swiftc -module-cache-path "$PWD/work/v2-cache" -parse-as-library \
  ios/App/Analytics.swift ios/App/BookingV2API.swift ios/App/BookingV2Models.swift ios/App/TravelProfileStore.swift \
  scripts/TravelProfileModelDemo.swift -o work/profile-model-tests/TravelProfileModelDemo
work/profile-model-tests/TravelProfileModelDemo "$@"
