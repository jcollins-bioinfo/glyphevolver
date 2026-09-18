# Catalog provenance and canonicalization

Sources are Unicode Emoji **17.0** `emoji-test.txt` and CLDR **48** English base annotations. Both are committed under `Vendor/Unicode` with the Unicode license. Source URLs:

- https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt
- https://github.com/unicode-org/cldr/blob/release-48/common/annotations/en.xml

Only `fully-qualified` entries are included; standalone components and qualification variants are excluded. Raw glyph strings are never split into individual tokens, so flags/keycaps/ZWJ sequences remain whole. Keywords come from CLDR base annotations when available; missing derived annotations use the source short name/group/subgroup instead. We do not claim complete CLDR keyword coverage.

`Scripts/build_catalog.py` runs offline over committed bytes. The report records source and generated-resource SHA-256 digests. Version: `unicode17-cldr48-canonical1-features1`.

| Quantity | Count |
|---|---:|
| Fully qualified raw sequences | 3,944 |
| Raw entries merged by canonicalization | 2,234 |
| Canonical concepts, all regimes | 1,710 |
| Concepts structurally excluded from Strict | 462 |
| Strict-eligible concepts before aesthetic filters | 1,248 |

Canonicalization removes skin-tone labels, maps man/woman to person and men/women to people, removes facing-right variants, collapses family structures, and merges a person-prefixed occupation with an exact official neutral-name concept when present. A representative is chosen by neutral tone, neutral gender, glyph length, then raw source ID. This deterministic English rule set is inspectable and intentionally conservative about occupations; editorial review of broader gender/family collapsing remains a release task.

Canonical names are sorted lexically to assign dense IDs. A catalog update can therefore change ranks: never reuse old ranks under a new version. Each concept retains all contributing raw IDs and a complete source RGI representative. Default eligibility excludes flags, keycaps, arrows, control/alphanumeric/geometric/math/punctuation/currency/other UI symbols and time variants. Wild retains these concepts subject to user exclusions.

Roles and visual features are explicitly heuristic, derived from source groups, subgroups and lexical classes in the script. They are not measured Apple rendering properties. There are no hidden model-generated numeric annotations. Localization is currently English; translated annotations should become a separate display layer so localized text does not renumber conceptual IDs or silently change scoring.
