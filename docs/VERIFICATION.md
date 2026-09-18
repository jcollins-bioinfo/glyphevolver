# Verification record — 2026-09-18

## Environment actually inspected

```sh
xcodebuild -version
xcodebuild -showsdks
swift --version
xcrun simctl list runtimes
xcrun simctl list devices available
```

Observed Xcode 16.3 / build 16E140, Swift 6.1, iOS and iOS Simulator SDK 18.4. With normal simulator-service access, both runtime and device lists were empty. The iOS 27 SDK and FoundationModels framework were not installed. Image Playground's installed interface exposed image-URL callbacks; the requested adaptive-glyph callback could not be verified locally. CoreText's adaptive image bounds/draw functions and UIKit's NSAdaptiveImageGlyph initializer/properties/attributed-string convenience were present in the installed headers.

Apple's newer flow is described at [WWDC26: Create high-quality images using Image Playground](https://developer.apple.com/videos/play/wwdc2026/375/) and the [adaptive-glyph sheet API](https://developer.apple.com/documentation/swiftui/view/imageplaygroundsheet%28ispresented%3Aconcept%3Asourceimageurl%3Aoncompletion%3Aonadaptiveimageglyphcreation%3Aoncancellation%3A%29). Online documentation was not treated as a substitute for inspecting the requested final installed SDK.

## Commands actually run and outcomes

```sh
python3 Scripts/build_catalog.py
python3 Scripts/generate_project.py
plutil -lint GlyphEvolver/PrivacyInfo.xcprivacy GlyphEvolver.xcodeproj/project.pbxproj
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/glyphevolver-module-cache CLANG_MODULE_CACHE_PATH=/private/tmp/glyphevolver-module-cache swift test --disable-sandbox
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/glyphevolver-module-cache CLANG_MODULE_CACHE_PATH=/private/tmp/glyphevolver-module-cache swift run --disable-sandbox -c release triplet-simulation 100000 artifacts/triplet_sampling_report.json
/bin/zsh Scripts/verify.sh
```

- Catalog/report/project/scheme regeneration: SHA-256 before/after equality **passed** for all four generated files.
- Plist/project syntax: **passed**.
- Final XCTest run: **17 tests, zero failures**, approximately 5.76 seconds. Includes exhaustive combinadic cases N=3...30 and all permutations, invalid/overflow input, PRNG reference vectors, catalog coverage/canonicalization, quality fixtures, regime constraints, deterministic sequences, exact mutations/pins, near/far behavior, category shift, recent/group filters, repeat identities/scopes, novelty, preference gates/directions/schema/reset, callback retry tokens/dismissal/limits/stop, prompt inheritance, SwiftData branches/reload/feedback/export/deletion.
- Swift Testing printed zero tests separately because this suite uses XCTest; that line does not negate the 17 XCTest results.
- Release build of `triplet-simulation`: **passed**.
- Full verification script: **exit 2**, after tests/simulation passed, because no iOS 27 simulator SDK exists. This is a blocked full verification, not a successful iOS verification.
- Some sandboxed runs printed SwiftPM cache-access warnings and CoreData notification-registration errors. Assertions and process exit for the test suite still passed. These environment messages are retained as limitations; no source compiler warnings remained in final type-checks.

## Final simulation

RNG seed: 20260918. Catalog: unicode17-cldr48-canonical1-features1; 1,710 concepts, 1,248 strict-eligible before aesthetic exclusions. Scoring: heuristic-1. Uniform distinct proposal distribution over the strict corpus after default exclusions.

| Metric | Observed |
|---|---:|
| Proposals evaluated | 100,000 |
| Accepted by strict rules | 24,454 (24.454%) |
| Mean total score | 0.67983 |
| Mean pair similarity | 0.02195 |
| Repeated uniform proposals | 0.015% |
| Scoring loop time | 0.796 s |
| Constructive selection, 10 batches | 7.27–8.20 ms |
| Median constructive selection | 7.66 ms |

Hardware is the local Apple Silicon Mac, **not an iPhone**. Timings are descriptive, not test assertions. The earlier scan-per-draw implementation took 0.35–0.47 s per batch; cached CDF draws plus conditional rejection reduced the work while preserving seeded constraints. A compact final summary is committed in `Resources/triplet_calibration_summary.json`; the fuller local report is `artifacts/triplet_sampling_report.json` and is intentionally ignored by Git.

## App source checking versus application build

The following source checks completed with exit 0 using normal macro-plugin access. They use the **installed iOS 18.4 headers** while retaining the requested iOS 27 target triple; they are not iOS 27 SDK verification or an application link/install/run:

```sh
mkdir -p /private/tmp/glyphevolver-ios-typecheck
xcrun swiftc -emit-module -parse-as-library -module-name GlyphCore -swift-version 6 \
  -target arm64-apple-ios27.0-simulator \
  -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk \
  -module-cache-path /private/tmp/glyphevolver-module-cache \
  -emit-module-path /private/tmp/glyphevolver-ios-typecheck/GlyphCore.swiftmodule \
  Sources/GlyphCore/*.swift .build/arm64-apple-macosx/debug/GlyphCore.build/DerivedSources/resource_bundle_accessor.swift
xcrun swiftc -typecheck -parse-as-library -module-name GlyphEvolver -swift-version 6 \
  -target arm64-apple-ios27.0-simulator \
  -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk \
  -module-cache-path /private/tmp/glyphevolver-module-cache \
  -I /private/tmp/glyphevolver-ios-typecheck GlyphEvolver/*.swift
```

Actual app build attempt:

```sh
xcodebuild -project GlyphEvolver.xcodeproj -scheme GlyphEvolver \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

With normal cache/service access, package resolution succeeded but Xcode returned **exit 70: no eligible destination**, reporting missing platform support. Initial sandboxed attempts also failed at cache permissions; retrying outside the sandbox separated that from the actual environment blocker. No simulator build, UI test, signed release/archive, or physical-device result is claimed.

## Source audit and version control

Product Swift source was searched for TODO, FIXME, fatalError, the prohibited generation API, network URLs/URLSession, UserDefaults, uptime, disk-capacity and timestamp API names. No matches were found. The draft privacy manifest still needs a final compiled binary/runtime audit. `git diff --check` and staged whitespace checks passed.

The local branch is `codex/initial-glyphevolver-app`, with origin set to the confirmed `jcollins-bioinfo/glyphevolver` URL. Command-line authentication was unavailable (Git HTTPS credential failure; gh HTTP 401). Local commits are the deliverable; no push/PR/merge occurred. Run `git log --oneline` for the exact committed sequence.

The request remains incomplete. See `IMPLEMENTATION_STATUS.md` for native integration, UI, device, privacy and App Store work still required.
