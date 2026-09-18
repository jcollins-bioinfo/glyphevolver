# Evolution semantics

The system is an interactive search metaphor, not biological evolution.

The core engine accepts three canonical parent IDs, optional phenotype, settings, pinned slot indices, scoped history, a preference model and an explicit SplitMix64 checkpoint. Pin constraints are never relaxed. In Evolution mode exactly mutationCount unpinned slots change; replacement IDs exclude every parent ID so the number of changed concepts cannot be defeated by swapping slots. An impossible count (for example 2 changes with 2 pins) throws exhaustion. Outside Evolution, all unpinned slots receive newly sampled candidates.

Mutation Random has no semantic multiplier. Semantic Near multiplies candidate weight by `exp(6(1−strength)s)`; strength 0 favors near matches, strength 1 broadens to the underlying regime prior. Semantic Far multiplies by `exp(6·strength·(1−s))`; increasing strength favors distant concepts. Category Shift requires a different subgroup and multiplies by `0.2+s`. When phenotype semantic tokens exist, s blends old-seed similarity and candidate/phenotype token Jaccard using semanticCarryover; otherwise it uses old-seed similarity. Crossover explicitly throws unavailableCrossover.

RecentWindow counts the most recent accepted generations across the active run, including branches. Replacements cannot use their IDs; retained parent/pinned IDs are exempt. The current store loads up to 100 recent generations and the UI limits the window to 30. Pure engine callers can provide longer histories. Exact unordered no-repeat is checked after mutation; currentRun/allHistory queries are scoped to catalogVersion.

The fallback phenotype analyzer extracts stable normalized semantic tokens from contentDescription plus seed subjects/subgroups. It makes no claim to infer actual colors, visual anatomy, or image quality. The dedicated prompt builder includes every selected named concept and its role. Parent description is included only for Evolution semantic/hybrid inheritance with carryover above zero. Visual-only inheritance excludes semantic parent text. The actual system source-image path is pending iOS 27 host integration.

The development shell evolves prepared seed triples. The completed product must use the accepted node as parent according to previous/manual policy, record a branch identifier when appropriate, and snapshot the exact settings, phenotype and prompt. Store parentage and snapshots already support this; native orchestration is unfinished.
