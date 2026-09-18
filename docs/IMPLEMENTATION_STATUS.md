# Implementation status and next handoff

This is an incomplete application milestone. The original brief and intelligent-search addendum are **not fully satisfied**.

## Environment and repository blockers

- Installed Xcode: 16.3 (16E140); Swift 6.1; iOS/device and simulator SDKs: 18.4. No alternative Xcode installation found.
- An unsandboxed `xcrun simctl list runtimes` and `list devices available` returned empty lists.
- Installed Image Playground sheet overloads return `URL`; no `onAdaptiveImageGlyphCreation` or emoji style was found in that SDK. FoundationModels is absent.
- Online Apple documentation describes the newer adaptive-glyph callback, but the requested installed final iOS 27 interface cannot be inspected here. No signature was guessed into production code.
- GitHub connector confirmed private `jcollins-bioinfo/glyphevolver`, size zero. HTTPS clone failed for missing credentials; `gh` returned HTTP 401. The workspace was initialized locally with the confirmed origin URL. It is not a successful remote clone and changes have not been published.

## Delivered boundaries

The search, arithmetic, preference, prompt, fallback phenotype, state reducer, and SwiftData persistence paths are implemented and tested on macOS. The iOS source can be checked separately against installed headers, but that does not establish an iOS 27 build, simulator run, or device integration.

Native data fields preserve binary `imageContent`, content ID, and description without PNG conversion. The persistence test fixture is synthetic and validates storage mechanics only. Attributed glyph display and CoreText raster rendering are adapters awaiting real glyph input.

## Unfinished release requirements

1. Install/select Xcode 27 and an iOS 27 simulator. Inspect actual final SDK interfaces, then implement `ImagePlaygroundHost` using the supported sheet, locked emoji style, capability environment, adaptive glyph callback, cancellation, and genuine dismissal notification. Wire it to the tested coordinator. Do not substitute URL-image creation. `ImageCreator` is prohibited.
2. Integrate accepted-parent phenotype, native visual source image, semantic/hybrid inheritance, parent policy, finite limits, background handling, and auto-advance. These settings/reducer primitives exist but the system flow does not.
3. Implement Foundation Models structured phenotype and optional batched critic with availability checks, timeout/cancellation/cache, validation and deterministic fallback. No Foundation Models runtime path exists yet; the fallback analyzer is implemented.
4. Finish run selection, manual searchable emoji replacement, per-slot reroll, run deletion confirmation, native lineage preview, visible feedback status, generation transition announcements, accessibility/visual QA, and metadata export UI validation. The store supports deletion, but the shell currently has no delete-run action.
5. Add iOS integration/UI targets, durable on-disk relaunch/migration tests, corruption/device rendering tests, scene interruption and cancellation stress tests, and device copy/share checks. Current tests are macOS XCTest; no simulator tests or real native generation passed.
6. Add actual post-generation retention/role/drift proxies, distinct scoring provenance for optional model critique, and versioned behavior-signal timestamps. Current behavior records keep a signal sequence plus last-updated time. The optional critic score is absent rather than fabricated.
7. Add production icon/localization catalogs, signing/team/bundle-ID decisions, distribution archive, privacy binary/runtime audit, final legal/metadata URLs and actual screenshots. No final icon, signed archive, or App Store submission exists.
8. Complete product CI only after confirming a compatible Xcode 27 runner. No knowingly broken iOS workflow is installed.

Two-parent crossover, population/sibling mode, native-rich-copy interoperability, and a binary full archive remain future features. The current copy action is correctly labeled Copy Description.

## Deliberate decisions

- Distinct canonical concepts are mandatory in every search regime: the addendum's uniqueness rule takes precedence over the earlier optional duplicate toggle.
- Impossible pin/mutation/filter/no-repeat constraints fail explicitly; the engine never silently relaxes them. A zero-mutation request can be impossible under current-run no-repeat after acceptance.
- All-history means all retained local history in the **same catalog namespace**. Deleting a run deletes its repeat entries, ratings, and signals, and rebuilds the preference model.
- Catalog IDs are dense, zero-based, and tied to a catalog version. The canonicalizer's English lexical mappings and heuristic features require further editorial review before release.
- No paid service, usage reset, external-generation backend, or added runtime dependency is used.
