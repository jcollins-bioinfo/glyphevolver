import Foundation

public struct SearchCandidate: Codable, Sendable {
    public let tripletID: TripletID
    public let conceptIDs: [Int]
    public let catalogVersion, scoringVersion: String
    public let regime: SamplingRegime
    public let score: TripletScore
    public let preferenceScore: Double?
    public let finalCandidateScore: Double
    public let preferenceModelVersion: String
}
public struct SearchHistory: Sendable {
    public var runSeen: Set<TripletID> = []
    public var allSeen: Set<TripletID> = []
    public var recentGenerations: [[Int]] = []
    public init() {}
    public func seen(for scope: NoRepeatScope) -> Set<TripletID> {
        switch scope { case .none: []; case .currentRun: runSeen; case .allHistory: allSeen }
    }
}
public struct TripletSearchEngine: Sendable {
    public let catalog: EmojiCatalog
    public let config: TripletScoringConfiguration
    public init(catalog: EmojiCatalog, config: TripletScoringConfiguration = .init()) {
        self.catalog = catalog; self.config = config
    }
    public func select(settings: EvolutionSettings, parent: [Int]? = nil, pins: Set<Int> = [],
                       history: SearchHistory = .init(), preferences: PreferenceModel = .init(), phenotype: Phenotype? = nil,
                       rng: inout SplitMix64) throws -> SearchCandidate {
        guard (0...3).contains(settings.mutationCount), settings.recentWindow >= 0,
              [settings.novelty,settings.mutationStrength,settings.semanticCarryover].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              config.poolSize > 0, config.maxAttempts >= config.poolSize, config.temperature.isFinite, config.temperature > 0,
              (0...1).contains(config.explorationProbability), pins.allSatisfy({ (0..<3).contains($0) }) else { throw SearchError.invalidSettings }
        if settings.mutation == .crossover { throw SearchError.unavailableCrossover }
        if let parent {
            guard parent.count==3, Set(parent).count==3, parent.allSatisfy(catalog.concepts.indices.contains) else { throw SearchError.invalidTriplet }
        } else if !pins.isEmpty { throw SearchError.invalidSettings }
        let recent = Set(history.recentGenerations.suffix(settings.recentWindow).flatMap { $0 })
        let seen = history.seen(for: settings.noRepeat)
        let eligible = catalog.concepts.filter {
            (settings.regime != .strictCurated || $0.defaultEligibility == .strict)
            && settings.excludedTags.isDisjoint(with: $0.exclusions)
            && (settings.allowedGroups.isEmpty || settings.allowedGroups.contains($0.group))
            && (settings.includeZWJ || !$0.isZWJSequence)
        }
        let eligibleIDs = Set(eligible.map(\.id))
        let inherited = settings.evolution && parent != nil
        let availableSlots = (0..<3).filter { !pins.contains($0) }
        let count = inherited ? settings.mutationCount : availableSlots.count
        guard count <= availableSlots.count, eligible.count >= 3 else { throw SearchError.exhausted }
        let similarity = LocalSimilarity(concepts: catalog.concepts)
        let scorer = TripletScorer(config: config, similarity: similarity)
        let phenotypeTokens=LocalSimilarity.tokens((phenotype?.semanticTraits ?? []).joined(separator:" "))
        var distributions: [String:WeightedDistribution]=[:]
        var slotCandidates: [Int:[EmojiConcept]]=[:]
        for slot in 0..<3 {
            let old=parent.map { catalog.concepts[$0[slot]] }
            slotCandidates[slot]=eligible.filter { c in
                !recent.contains(c.id) && (!inherited || !(parent ?? []).contains(c.id))
                && !(inherited && settings.mutation == .categoryShift && old?.subgroup==c.subgroup)
            }
        }
        var pool: [SearchCandidate] = [], poolIDs: Set<TripletID> = []
        for _ in 0..<config.maxAttempts {
            var slots = availableSlots
            // Explicit Fisher-Yates using this run's PRNG, never global randomness.
            if slots.count > 1 {
                for i in stride(from: slots.count-1, through: 1, by: -1) { slots.swapAt(i,rng.index(count:i+1)) }
            }
            let changed = Set(slots.prefix(count))
            var ids = parent ?? [-1,-1,-1]
            for i in changed { ids[i] = -1 }
            guard ids.filter({ $0 >= 0 }).allSatisfy(eligibleIDs.contains) else { throw SearchError.exhausted }
            let template = RoleTemplate.allCases[rng.weightedIndex(RoleTemplate.allCases.map(\.prior)) ?? 0]
            var failed = false
            for slot in 0..<3 where ids[slot] < 0 {
                let old = parent.map { catalog.concepts[$0[slot]] }
                let candidates = slotCandidates[slot] ?? []
                let key="\(template.rawValue)|\(slot)"
                if distributions[key]==nil {
                    let weights = candidates.map { c -> Double in
                        var weight = settings.regime == .strictCurated ? pow(template.suitability(c,slot:slot),2)*c.visualFeatures.visualSalience : 1
                        if inherited, let old {
                            var s = similarity.similarity(c,old)
                            if !phenotypeTokens.isEmpty {
                                let tokens=LocalSimilarity.tokens(c.canonicalName+" "+c.keywords.joined(separator:" "))
                                let overlap=Double(tokens.intersection(phenotypeTokens).count)/Double(max(1,tokens.union(phenotypeTokens).count))
                                s=(1-settings.semanticCarryover)*s+settings.semanticCarryover*overlap
                            }
                            switch settings.mutation {
                            case .semanticNear: weight *= exp((1-settings.mutationStrength)*6*s)
                            case .semanticFar: weight *= exp(settings.mutationStrength*6*(1-s))
                            case .categoryShift: weight *= 0.2+s
                            case .random, .crossover: break
                            }
                        }
                        return weight
                    }
                    distributions[key]=WeightedDistribution(weights)
                }
                guard let distribution=distributions[key] else { failed=true; break }
                // Rejection sampling gives the conditional nonredundancy distribution without scanning the corpus for every draw.
                var selected: EmojiConcept?
                for _ in 0..<32 {
                    let c=candidates[distribution.sample(using:&rng)]
                    if ids.contains(c.id) { continue }
                    let probability = settings.regime == .wild ? 1 : ids.filter { $0>=0 }.reduce(1.0) {
                        $0*max(0.01,1-similarity.similarity(c,catalog.concepts[$1]))
                    }
                    if rng.unit()<probability { selected=c; break }
                }
                guard let selected else { failed=true; break }
                ids[slot] = selected.id
            }
            if failed { continue }
            let concepts = ids.map { catalog.concepts[$0] }
            let evaluation = try scorer.evaluate(concepts,settings:settings,recent:recent,seen:seen)
            guard evaluation.accepted else { continue }
            let id = try TripletID(conceptIDs:(ids[0],ids[1],ids[2]))
            guard poolIDs.insert(id).inserted else { continue }
            let preference = settings.preferenceLearning ? preferences.predict(evaluation.score.features) : nil
            let final = preference.map { 0.85*evaluation.score.total + 0.15*$0 } ?? evaluation.score.total
            pool.append(.init(tripletID:id,conceptIDs:ids,catalogVersion:catalog.version,scoringVersion:config.version,
                regime:settings.regime,score:evaluation.score,preferenceScore:preference,finalCandidateScore:final,
                preferenceModelVersion:PreferenceModel.version))
            if pool.count >= config.poolSize { break }
        }
        guard !pool.isEmpty else { throw SearchError.exhausted }
        pool.sort { $0.finalCandidateScore == $1.finalCandidateScore ? $0.tripletID.rawValue < $1.tripletID.rawValue : $0.finalCandidateScore > $1.finalCandidateScore }
        if rng.unit() < config.explorationProbability {
            let novel = pool.sorted { $0.score.novelty == $1.score.novelty ? $0.tripletID.rawValue < $1.tripletID.rawValue : $0.score.novelty > $1.score.novelty }
            return novel[rng.index(count:min(12,novel.count))]
        }
        let shortlist = Array(pool.prefix(12)), maximum = shortlist[0].finalCandidateScore
        let weights = shortlist.map { exp(($0.finalCandidateScore-maximum)/config.temperature) }
        return shortlist[rng.weightedIndex(weights) ?? 0]
    }
}

public struct Phenotype: Codable, Sendable {
    public let dominantSubjects, visualTraits, semanticTraits: [String]
    public let tone, provenance: String
}
public protocol PhenotypeAnalyzing: Sendable { func analyze(description: String, seeds: [EmojiConcept]) async throws -> Phenotype }
public struct FallbackPhenotypeAnalyzer: PhenotypeAnalyzing {
    public init() {}
    public func analyze(description: String, seeds: [EmojiConcept]) async throws -> Phenotype {
        .init(dominantSubjects: seeds.map(\.canonicalName), visualTraits: seeds.map(\.subgroup),
              semanticTraits: LocalSimilarity.tokens(description).sorted(), tone:"unspecified",provenance:"local-token-analysis-1")
    }
}
public protocol GenerationPromptBuilding { func build(seeds: [EmojiConcept], parentDescription: String?, settings: EvolutionSettings, roles: RoleAssignment) -> String }
public struct GenerationPromptBuilder: GenerationPromptBuilding {
    public init() {}
    public func build(seeds: [EmojiConcept], parentDescription: String?, settings: EvolutionSettings, roles: RoleAssignment) -> String {
        let roleText = roles.conceptIDs.enumerated().compactMap { i,id in
            seeds.first(where: { $0.id==id }).map { "\($0.canonicalGlyph) \($0.canonicalName): \(roles.template.roles[i].rawValue)" }
        }.joined(separator:"; ")
        var result = "Create one coherent adaptive emoji glyph integrating all three concepts: \(roleText). Use one dominant entity transformed by the other concepts. Preserve recognizable aspects of each; avoid three separate objects side by side."
        if settings.evolution, settings.inheritance != .visual, settings.semanticCarryover > 0, let parentDescription {
            result += " Parent description (reference material): \(parentDescription). Preserve approximately \(Int(settings.semanticCarryover*100)) percent of its semantic character."
        }
        return result
    }
}
