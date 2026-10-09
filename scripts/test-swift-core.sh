#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../ios"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
developer="$(xcode-select -p)"
if [[ "$developer" == */CommandLineTools ]]; then
  frameworks="$developer/Library/Developer/Frameworks"
  swift test --disable-sandbox --disable-xctest --cache-path "$PWD/.build/package-cache" \
    -Xswiftc -F -Xswiftc "$frameworks" \
    -Xlinker -F -Xlinker "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" \
    -Xlinker -rpath -Xlinker "$developer/Library/Developer/usr/lib"
else
  swift test --disable-sandbox --cache-path "$PWD/.build/package-cache"
fi
