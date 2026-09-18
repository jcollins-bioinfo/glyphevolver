# GlyphEvolver

An independent native iOS project exploring **strange but visually composable** emoji combinations. Repository: `jcollins-bioinfo/glyphevolver`. The consumer product name is **GlyphEvolver**.

**Status: tested search/persistence foundation and SwiftUI development shell. Not an App Store-ready application.** Native iOS 27 Image Playground and Foundation Models integration remain blocked on installing the requested toolchain. The local environment has Xcode 16.3 / iOS 18.4 / Swift 6.1 and no simulator runtimes. See [implementation status](docs/IMPLEMENTATION_STATUS.md) and [verification results](docs/VERIFICATION.md) before treating any capability as complete.

## Implemented

- Bundled Unicode 17 / CLDR 48 catalog: 3,944 fully qualified emoji sequences, 1,710 canonical concepts, 1,248 strict-eligible concepts before user exclusions.
- Strict Curated, Exploratory, and Wild search; fuzzy compositional roles; all six role permutations; transparent heuristic scoring; single-entity potential; aesthetic/category/ZWJ constraints.
- SplitMix64, stable weighted sampling, mutation counts, pinned slots, semantic-near/far mutation, category shift, recent-use exclusion, exact unordered triplet IDs, and current-run/all-retained-history repeat policies.
- A pure generation callback coordinator with stale-session protection and an explicit dismissal barrier.
- Versioned SwiftData schema with branch parentage, external native-glyph binary storage, settings and score snapshots, a serialized acceptance boundary, explicit feedback, separate behavioral signals, and local preference-model state.
- Deterministic regularized logistic preference ranking after 12 informative ratings; metadata-only local JSON export.
- Four-tab SwiftUI development interface for preparing combinations and inspecting settings. It visibly explains that native generation is not connected.

The CoreText renderer and attributed-glyph view use signatures present in the installed SDK. They have **not** rendered a real accepted adaptive glyph during this task. Storage tests use synthetic bytes, not actual generated glyphs.

## Build and verify

The Xcode project and Swift package declare **iOS 27.0**. The app requires **Xcode 27** and a supported iOS 27 device for the intended native flow. The portable package also supports macOS 15+, enabling local tests independently of missing iOS infrastructure. No third-party runtime packages or network access are needed for builds.

```sh
open GlyphEvolver.xcodeproj
swift test --disable-sandbox
mkdir -p artifacts
swift run --disable-sandbox -c release triplet-simulation 100000 artifacts/triplet_sampling_report.json
Scripts/verify.sh --core-only
Scripts/verify.sh
```

`verify.sh` runs tests and simulation, then checks for iOS 27. It exits **2** if that SDK/runtime is missing. Even after installation, it exits **3** after the app build until native integration and iOS UI/integration tests are implemented; it deliberately cannot report full success for an unfinished product. The actual command results are in `docs/VERIFICATION.md`.

Rebuild bundled resources and project files offline:

```sh
python3 Scripts/build_catalog.py
python3 Scripts/generate_project.py
```

Use the committed source files in `Vendor/Unicode`; their digests are in `Resources/emoji_catalog_report.json`. Do not update the catalog in a shipped installation without preserving/migrating its concept-ID namespace. No application software license has been chosen. Unicode's data license is included separately.

## Evolution and reproducibility

Search combines a parent seed triple and optional deterministic phenotype with mutation settings. Pinned slots and mutation count are hard constraints. An impossible request produces a visible error. Strict quality filtering applies after mutation. Crossover is a reserved enum/schema value and is rejected until two-parent selection exists.

The development UI currently mutates **prepared seeds**; it does not pretend those are accepted native glyphs. Accepted-parent semantic/visual/hybrid integration, native sheet presentation, and auto-advance are unfinished. The core coordinator and settings provide those future integration boundaries.

**The seed reproduces GlyphEvolver's input-selection decisions, not Apple's generated image output.** Reproduction also requires the same catalog/scoring version, RNG checkpoint, settings, parent/phenotype, pins, history, and preference state. Prepared rerolls consume randomness and save the run checkpoint.

## Architecture

`Sources/GlyphCore` contains the catalog, combinadic math, scorer, selector, preference model, coordinator, and SwiftData store. `GlyphEvolver` contains the SwiftUI app and CoreText adapter. `Tests/GlyphCoreTests` exercises pure and persistence behavior. `Sources/TripletSimulation` provides offline calibration and benchmarking. `Scripts` rebuilds resources/project and verifies the repository. `docs` records formulas, scope, device checks, and conservative App Store drafts.

The SwiftData store uses no CloudKit configuration. There is no login, telemetry, remote model API, or third-party runtime dependency. Source auditing does not substitute for a final compiled-app privacy and runtime audit; see [privacy](PRIVACY.md).

Screenshots are intentionally pending a working supported simulator/device build; see [screenshot plan](docs/AppStore/screenshot-plan.md).

GlyphEvolver is not affiliated with or endorsed by Apple. Genmoji is an Apple trademark; Image Playground is referenced descriptively. No Apple artwork is used for branding.
