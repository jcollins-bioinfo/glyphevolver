#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/glyphevolver-module-cache"
export CLANG_MODULE_CACHE_PATH="$SWIFTPM_MODULECACHE_OVERRIDE"
swift test --disable-sandbox
mkdir -p artifacts
swift run --disable-sandbox -c release triplet-simulation 100000 artifacts/triplet_sampling_report.json > artifacts/triplet_sampling_stdout.json
if [ "${1:-}" = "--core-only" ]; then exit 0; fi
if ! xcodebuild -showsdks | /usr/bin/grep -q 'iphonesimulator27\.'; then
    echo 'BLOCKED: install and select Xcode 27 with an iOS 27 simulator SDK. Core checks passed; full iOS verification has NOT passed.' >&2
    exit 2
fi
simulator=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); ids=[v["udid"] for k,vs in d["devices"].items() if "iOS-27-" in k for v in vs if v.get("isAvailable")]; print(ids[0] if ids else "")')
if [ -z "$simulator" ]; then echo 'BLOCKED: no usable iOS 27 simulator.' >&2; exit 2; fi
xcodebuild -project GlyphEvolver.xcodeproj -scheme GlyphEvolver -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
echo 'BLOCKED: native integration and iOS UI/integration test targets remain unfinished; see docs/IMPLEMENTATION_STATUS.md.' >&2
exit 3
