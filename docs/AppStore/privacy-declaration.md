# Privacy declaration draft

Intended architecture: no developer-operated data collection, tracking, analytics, advertising, account or server. Local lineage, feedback and preference parameters remain in the app's SwiftData store. User-requested metadata export uses the selected system destination.

The inspected source and package dependency graph support this design. A completed native-generation build and runtime data-flow audit do not yet exist. **Do not submit “Data Not Collected” as a verified final declaration yet.** Review Apple's current App Store Connect questions, the native framework behavior, the final dependency graph and compiled privacy report immediately before submission.

Draft manifest: no declared tracking, collected types or required-reason APIs. Audit rationale is in `PRIVACY.md`; changes to runtime code require a fresh audit.
