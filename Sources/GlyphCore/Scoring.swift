import Foundation

public enum SamplingRegime: String, Codable, CaseIterable, Sendable { case strictCurated, exploratory, wild }
public enum NoRepeatScope: String, Codable, CaseIterable, Sendable { case none, currentRun, allHistory }
public enum MutationStrategy: String, Codable, CaseIterable, Sendable { case random, semanticNear, semanticFar, categoryShift, crossover }
public enum InheritanceStrategy: String, Codable, CaseIterable, Sendable { case semantic, visual, hybrid }
public enum RoleTemplate: String, Codable, CaseIterable, Sendable {
    case subjectFeatureSetting, subjectFeatureAccessory, subjectMaterialFeature, subjectObjectAtmosphere
    case objectMaterialFeature, objectFeatureSetting, characterAccessoryAtmosphere
    public var roles: [GenerativeRole] {
        switch self {
        case .subjectFeatureSetting, .objectFeatureSetting: [.subject,.feature,.setting]
        case .subjectFeatureAccessory: [.subject,.feature,.accessory]
        case .subjectMaterialFeature, .objectMaterialFeature: [.subject,.material,.feature]
        case .subjectObjectAtmosphere: [.subject,.accessory,.atmosphere]
        case .characterAccessoryAtmosphere: [.subject,.accessory,.emotionSymbol]
        }
    }
    public var prior: Double {
        switch self {
        case .subjectFeatureSetting: 1
        case .subjectFeatureAccessory, .subjectMaterialFeature: 0.95
        case .objectMaterialFeature: 0.90
        case .subjectObjectAtmosphere, .objectFeatureSetting: 0.85
        case .characterAccessoryAtmosphere: 0.80
        }
    }
    public func suitability(_ c: EmojiConcept, slot: Int) -> Double {
        if slot == 0 && (self == .objectMaterialFeature || self == .objectFeatureSetting) { return c.visualFeatures.objectness }
        if slot == 0 && self == .characterAccessoryAtmosphere { return c.visualFeatures.characterLikeness }
        if slot == 1 && self == .subjectObjectAtmosphere { return c.visualFeatures.objectness }
        return c.roles[roles[slot]]
    }
}
public struct RoleAssignment: Codable, Equatable, Sendable {
    public let template: RoleTemplate
    public let conceptIDs: [Int]
}
public struct TripletScoringConfiguration: Codable, Sendable {
    public var version = "heuristic-1"
    public var strictThreshold = 0.70
    public var anchorThreshold = 0.70
    public var redundancyThreshold = 0.88
    public var complexityCeiling = 2.1
    public var roleFitMinimum = 0.50
    public var poolSize = 64
    public var maxAttempts = 384
    public var explorationProbability = 0.10
    public var temperature = 0.20
    public init() {}
}
public struct EvolutionSettings: Codable, Equatable, Sendable {
    public var regime: SamplingRegime = .strictCurated
    public var noRepeat: NoRepeatScope = .currentRun
    public var evolution = true
    public var inheritance: InheritanceStrategy = .hybrid
    public var mutation: MutationStrategy = .random
    public var mutationCount = 1
    public var mutationStrength = 0.5
    public var semanticCarryover = 0.75
    public var novelty = 0.35
    public var recentWindow = 4
    public var autoAdvance = true
    public var generationLimit: Int? = nil
    public var excludedTags: Set<String> = ["waste", "illness", "injury"]
    public var allowedGroups: Set<String> = []
    public var includeZWJ = true
    public var preferenceLearning = true
    public init() {}
}
public protocol ConceptSimilarityScoring: Sendable {
    func similarity(_ lhs: EmojiConcept, _ rhs: EmojiConcept) -> Double
}
public struct LocalSimilarity: ConceptSimilarityScoring {
    private let cached: [Int:Set<String>]
    public init(concepts: [EmojiConcept] = []) {
        cached = Dictionary(uniqueKeysWithValues: concepts.map { ($0.id, Self.tokens($0.canonicalName + " " + $0.keywords.joined(separator:" "))) })
    }
    public static func tokens(_ text: String) -> Set<String> {
        let aliases = ["feline":"cat", "kitty":"cat", "lunar":"moon", "galaxy":"space", "cosmic":"space", "flame":"fire", "icy":"ice"]
        let stop: Set<String> = ["and","with","the","of","a","an","in","on"]
        return Set(text.precomposedStringWithCanonicalMapping.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stop.contains($0) }.map { aliases[$0] ?? $0 })
    }
    public func similarity(_ a: EmojiConcept, _ b: EmojiConcept) -> Double {
        if a.id == b.id { return 1 }
        let x = cached[a.id] ?? Self.tokens(a.canonicalName + " " + a.keywords.joined(separator: " "))
        let y = cached[b.id] ?? Self.tokens(b.canonicalName + " " + b.keywords.joined(separator: " "))
        let j = Double(x.intersection(y).count) / Double(max(1,x.union(y).count))
        return clamp(0.65*j + (a.group==b.group ? 0.10 : 0) + (a.subgroup==b.subgroup ? 0.25 : 0))
    }
}
public enum TripletRejectionReason: String, Codable, CaseIterable, Sendable {
    case duplicate, excludedConcept, noVisualAnchor, excessiveAbstraction, competingSubjects
    case threeHumanCharacters, threeFaces, excessiveRedundancy, excessiveComplexity, roleFitTooLow, qualityBelowThreshold
}
public struct TripletScore: Codable, Equatable, Sendable {
    public let anchor, roleFit, visualCompatibility, singleEntityPotential, novelty, semanticCoherence: Double
    public let redundancyPenalty, clutterPenalty, competitionPenalty, meanPairSimilarity, maxPairSimilarity: Double
    public let total: Double
    public let bestRoleAssignment: RoleAssignment
    public var features: [Double] {
        [anchor,roleFit,visualCompatibility,singleEntityPotential,novelty,semanticCoherence,
         redundancyPenalty,clutterPenalty,competitionPenalty,meanPairSimilarity,maxPairSimilarity]
        + RoleTemplate.allCases.map { $0==bestRoleAssignment.template ? 1 : 0 }
    }
}
public struct TripletEvaluation: Sendable {
    public let score: TripletScore
    public let reasons: [TripletRejectionReason]
    public var accepted: Bool { reasons.isEmpty }
}
public struct TripletScorer: Sendable {
    public let config: TripletScoringConfiguration
    private let similarity: LocalSimilarity
    public init(config: TripletScoringConfiguration = .init(), similarity: LocalSimilarity = .init()) { self.config = config; self.similarity = similarity }
    public func evaluate(_ c: [EmojiConcept], settings: EvolutionSettings = .init(), recent: Set<Int> = [], seen: Set<TripletID> = []) throws -> TripletEvaluation {
        guard c.count==3 else { throw SearchError.invalidTriplet }
        let id = try TripletID(conceptIDs: (c[0].id,c[1].id,c[2].id))
        let sim = similarity
        let pairs = [sim.similarity(c[0],c[1]),sim.similarity(c[0],c[2]),sim.similarity(c[1],c[2])]
        let mean = pairs.reduce(0,+)/3, maximum = pairs.max() ?? 0
        let permutations = [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]]
        var fit = -1.0, assignment = RoleAssignment(template: .subjectFeatureSetting, conceptIDs: c.map(\.id))
        var ordered = c
        for template in RoleTemplate.allCases {
            for p in permutations {
                let score = pow(template.suitability(c[p[0]],slot:0)*template.suitability(c[p[1]],slot:1)*template.suitability(c[p[2]],slot:2), 1.0/3)*template.prior
                if score > fit { fit = score; ordered = p.map { c[$0] }; assignment = .init(template: template, conceptIDs: ordered.map(\.id)) }
            }
        }
        let v = c.map(\.visualFeatures)
        let anchor = c.map { 0.45*$0.roles.subject + 0.35*$0.visualFeatures.objectness + 0.20*$0.visualFeatures.visualSalience }.max() ?? 0
        let complexity = v.map(\.intrinsicComplexity).reduce(0,+)
        let modifiers = (ordered[1].visualFeatures.transformability + ordered[2].visualFeatures.transformability)/2
        let competition = c.map { $0.roles.subject * (1-$0.visualFeatures.transformability) }.min() ?? 0
        let clutter = clamp((complexity + 0.5*v.map(\.sceneLikeness).reduce(0,+))/4.5)
        let single = clamp(0.5*max(ordered[0].roles.subject,ordered[0].visualFeatures.objectness) + 0.5*modifiers - 0.15*competition)
        let visual = clamp(0.35*anchor + 0.40*modifiers + 0.25*(1-clutter))
        let goldilocks = exp(-pow(mean-0.30,2)/(2*0.20*0.20))
        let reuse = Double(c.filter { recent.contains($0.id) }.count)/3
        let novelty = (1-settings.novelty) + settings.novelty*goldilocks*(1-reuse)
        let coherence = clamp(0.5*fit + 0.5*min(1,mean/0.30))
        let redundancy = clamp((maximum-0.5)/0.5)
        let total = clamp((0.20*fit + 0.18*visual + 0.15*single + 0.15*anchor + 0.12*novelty + 0.08*coherence
            - 0.12*redundancy - 0.12*clutter - 0.08*competition)/0.88)
        let score = TripletScore(anchor: anchor, roleFit: fit, visualCompatibility: visual, singleEntityPotential: single,
            novelty: novelty, semanticCoherence: coherence, redundancyPenalty: redundancy, clutterPenalty: clutter,
            competitionPenalty: competition, meanPairSimilarity: mean, maxPairSimilarity: maximum,
            total: total, bestRoleAssignment: assignment)
        var reasons: [TripletRejectionReason] = []
        if seen.contains(id) { reasons.append(.duplicate) }
        if c.contains(where: { !settings.excludedTags.isDisjoint(with: $0.exclusions) || (!settings.allowedGroups.isEmpty && !settings.allowedGroups.contains($0.group)) || (!settings.includeZWJ && $0.isZWJSequence) }) { reasons.append(.excludedConcept) }
        if settings.regime == .strictCurated {
            if c.contains(where: { $0.defaultEligibility != .strict }) { reasons.append(.excludedConcept) }
            if anchor < config.anchorThreshold { reasons.append(.noVisualAnchor) }
            if v.allSatisfy({ $0.symbolicness >= 0.7 && $0.concreteness <= 0.4 }) { reasons.append(.excessiveAbstraction) }
            if c.allSatisfy({ $0.roles.subject >= 0.8 && $0.visualFeatures.transformability < 0.45 }) { reasons.append(.competingSubjects) }
            if c.allSatisfy(\.isHuman) { reasons.append(.threeHumanCharacters) }
            if c.allSatisfy(\.isFace) { reasons.append(.threeFaces) }
            if pairs.filter({ $0 >= config.redundancyThreshold }).count >= 2 { reasons.append(.excessiveRedundancy) }
            if complexity > config.complexityCeiling { reasons.append(.excessiveComplexity) }
            if fit < config.roleFitMinimum { reasons.append(.roleFitTooLow) }
            if total < config.strictThreshold { reasons.append(.qualityBelowThreshold) }
        } else if settings.regime == .exploratory && total < 0.45 { reasons.append(.qualityBelowThreshold) }
        return .init(score: score, reasons: reasons)
    }
}
