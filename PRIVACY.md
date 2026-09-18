# Privacy implementation status

The implemented source contains no backend client, analytics SDK, advertising SDK, crash-reporting SDK, remote model service, API keys, account system or automatic telemetry. `Package.swift` declares no external dependencies. SwiftData is configured with `cloudKitDatabase: .none`. Catalog regeneration reads committed local files and does not fetch during an app build.

Local records include run seeds/settings/checkpoints, prepared/accepted lineage metadata, accepted native glyph bytes when the host is implemented, explicit ratings, separate behavioral signals and a small preference-model snapshot. JSON export is initiated by the user and deliberately excludes native glyph binaries. The operating system's export destination is chosen by the user.

GlyphEvolver may learn from ratings and local interaction history to improve which emoji combinations it proposes. This preference model and its training data remain on the user's device and are not transmitted to a server. **Current implementation detail:** only explicit ratings train the model; behavioral signals are stored separately for potential future interpretation. No cloud synchronization is configured. OS-level device backup behavior is separate from app-managed cloud sync and has not been audited.

The native Image Playground and Foundation Models runtime integrations are not implemented, so their final data flow has not been verified. A final compiled application/dependency and runtime audit is required before an App Store declaration of “data not collected.” The current source audit is preliminary evidence, not a completed release declaration.

The draft privacy manifest lists no tracking, collection, tracking domains or required-reason API use. Direct source inspection found no UserDefaults, system-uptime, disk-capacity or file-timestamp APIs in app logic. SwiftData/framework internals and final binary signatures must still be audited. The manifest must be revised if later implementation introduces required-reason APIs; no reason is invented preemptively.
