#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work/v2-model-tests
swiftc -module-cache-path "$PWD/work/v2-cache" -parse-as-library \
  ios/App/Analytics.swift ios/App/BookingV2API.swift ios/App/BookingV2Models.swift ios/App/BookingV2Store.swift \
  scripts/BookingV2ModelDemo.swift -o work/v2-model-tests/BookingV2ModelDemo
work/v2-model-tests/BookingV2ModelDemo "$@"
