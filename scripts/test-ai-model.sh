#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work/ai-model-tests
cache="$PWD/ios/.build/swift-cache"
swiftc -module-cache-path "$cache" -emit-module -emit-library -module-name TripFitCore \
  ios/Sources/TripFitCore/*.swift -o work/ai-model-tests/libTripFitCore.dylib \
  -emit-module-path work/ai-model-tests/TripFitCore.swiftmodule
swiftc -module-cache-path "$cache" -parse-as-library \
  -I work/ai-model-tests -L work/ai-model-tests -lTripFitCore \
  -Xlinker -rpath -Xlinker "$PWD/work/ai-model-tests" \
  ios/App/Analytics.swift ios/App/AIPlanning.swift ios/App/BackendAPI.swift ios/App/BookingStore.swift \
  scripts/AIModelDemo.swift -o work/ai-model-tests/AIModelDemo
work/ai-model-tests/AIModelDemo
