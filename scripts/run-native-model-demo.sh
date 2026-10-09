#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work/swift-harness
cache="$PWD/ios/.build/swift-cache"
swiftc -module-cache-path "$cache" -emit-module -emit-library -module-name TripFitCore \
  ios/Sources/TripFitCore/*.swift -o work/swift-harness/libTripFitCore.dylib \
  -emit-module-path work/swift-harness/TripFitCore.swiftmodule
swiftc -module-cache-path "$cache" -parse-as-library \
  -I work/swift-harness -L work/swift-harness -lTripFitCore \
  -Xlinker -rpath -Xlinker "$PWD/work/swift-harness" \
  ios/App/Analytics.swift ios/App/BackendAPI.swift ios/App/AIPlanning.swift ios/App/BookingStore.swift \
  scripts/NativeModelDemo.swift -o work/swift-harness/TripFitNativeModelDemo
work/swift-harness/TripFitNativeModelDemo
