import Foundation

public enum EligibilityClass: String, Codable, Sendable { case strict, exploratoryOnly }
public enum GenerativeRole: String, Codable, CaseIterable, Sendable {
    case subject, feature, material, accessory, setting, atmosphere, emotionSymbol
}
public struct GenerativeRoleScores: Codable, Hashable, Sendable {
    public var subject, feature, material, accessory, setting, atmosphere, emotionSymbol: Double
    public subscript(_ role: GenerativeRole) -> Double {
        switch role {
        case .subject: subject; case .feature: feature; case .material: material
        case .accessory: accessory; case .setting: setting; case .atmosphere: atmosphere
        case .emotionSymbol: emotionSymbol
        }
    }
}
public struct VisualFeatureVector: Codable, Hashable, Sendable {
    public var concreteness, visualSalience, objectness, characterLikeness: Double
    public var sceneLikeness, symbolicness, intrinsicComplexity, transformability: Double
}
public struct RawEmoji: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let glyph, shortName, group, subgroup: String
    public let keywords: [String]
    public let isFlag, isKeycap, isSkinToneVariant, isGenderVariant, isZWJSequence: Bool
}
public struct EmojiConcept: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let canonicalGlyph, canonicalName, group, subgroup: String
    public let rawEmojiIDs: [Int]
    public let keywords, exclusions: [String]
    public let roles: GenerativeRoleScores
    public let visualFeatures: VisualFeatureVector
    public let defaultEligibility: EligibilityClass
    public let isFace, isHuman, isZWJSequence: Bool
}
public struct EmojiCatalog: Codable, Sendable {
    public let version: String
    public let raw: [RawEmoji]
    public let concepts: [EmojiConcept]
    public static func bundled() throws -> Self {
        guard let url = Bundle.module.url(forResource: "emoji_catalog", withExtension: "json") else {
            throw SearchError.invalidCatalog
        }
        let catalog = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard catalog.concepts.map(\.id) == Array(catalog.concepts.indices), catalog.concepts.count >= 3 else {
            throw SearchError.invalidCatalog
        }
        return catalog
    }
}
public enum SearchError: Error, Equatable, LocalizedError {
    case invalidCatalog, invalidTriplet, overflow, exhausted, invalidSettings, unavailableCrossover
    public var errorDescription: String? {
        switch self {
        case .invalidCatalog: "The bundled emoji catalog could not be loaded."
        case .invalidTriplet: "Choose three distinct concepts from this catalog."
        case .overflow: "The combination space exceeds the supported integer range."
        case .exhausted: "No candidates satisfy these filters, pins, mutation count, and repeat policy. Try changing a constraint."
        case .invalidSettings: "The search settings are outside their supported range."
        case .unavailableCrossover: "Crossover requires two-parent selection, which is not available yet."
        }
    }
}
func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

public struct SplitMix64: RandomNumberGenerator, Codable, Sendable {
    public private(set) var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
    public mutating func unit() -> Double { Double(next() >> 11) / 9_007_199_254_740_992 }
    public mutating func index(count: Int) -> Int {
        precondition(count > 0)
        let bound = UInt64(count), threshold = (0 &- bound) % bound
        var value = next()
        while value < threshold { value = next() }
        return Int(value % bound)
    }
    public mutating func weightedIndex(_ weights: [Double]) -> Int? {
        guard !weights.isEmpty, weights.allSatisfy({ $0.isFinite && $0 >= 0 }),
              let maximum = weights.max(), maximum > 0 else { return nil }
        let scaled = weights.map { $0 / maximum }, total = scaled.reduce(0, +)
        var draw = unit() * total
        for i in scaled.indices {
            draw -= scaled[i]
            if draw < 0 { return i }
        }
        return scaled.lastIndex(where: { $0 > 0 })
    }
}

/// Immutable CDF permits repeated weighted draws in O(log N).
struct WeightedDistribution {
    private let cumulative: [Double]
    private let total: Double
    init?(_ weights: [Double]) {
        guard weights.allSatisfy({ $0.isFinite && $0>=0 }), let maximum=weights.max(), maximum>0 else { return nil }
        var sum=0.0
        cumulative=weights.map { sum += $0/maximum; return sum }
        total=sum
    }
    func sample(using rng: inout SplitMix64) -> Int {
        let draw=rng.unit()*total
        var low=0, high=cumulative.count-1
        while low<high {
            let mid=low+(high-low)/2
            if cumulative[mid]>draw { high=mid } else { low=mid+1 }
        }
        return low
    }
}

/// Integer binomial coefficient, with cancellation before checked multiplication.
public func choose(_ n: UInt64, _ k: UInt64) throws -> UInt64 {
    guard k <= 3 else { throw SearchError.invalidSettings }
    if k > n { return 0 }
    if k == 0 { return 1 }
    if k == 1 { return n }
    var factors = (0..<k).map { n - $0 }
    for divisor in 2...k {
        var remaining = divisor
        for i in factors.indices {
            var a = factors[i], b = remaining
            while b != 0 { (a,b) = (b,a % b) }
            factors[i] /= a
            remaining /= a
        }
    }
    var result: UInt64 = 1
    for factor in factors {
        let (value, overflow) = result.multipliedReportingOverflow(by: factor)
        guard !overflow else { throw SearchError.overflow }
        result = value
    }
    return result
}
public struct TripletID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public init(conceptIDs: (Int, Int, Int)) throws {
        let ids = [conceptIDs.0, conceptIDs.1, conceptIDs.2].sorted()
        guard ids[0] >= 0, Set(ids).count == 3 else { throw SearchError.invalidTriplet }
        var rank: UInt64 = 0
        for (i, id) in ids.enumerated() {
            let term = try choose(UInt64(id), UInt64(i+1))
            let (value, overflow) = rank.addingReportingOverflow(term)
            guard !overflow else { throw SearchError.overflow }
            rank = value
        }
        rawValue = rank
    }
}
public func conceptIDs(for id: TripletID, catalogSize: Int) throws -> (Int,Int,Int) {
    guard catalogSize >= 3, id.rawValue < (try choose(UInt64(catalogSize),3)) else { throw SearchError.invalidTriplet }
    var remaining = id.rawValue, ceiling = catalogSize - 1, result = [Int](repeating: 0, count: 3)
    for k in stride(from: 3, through: 1, by: -1) {
        var lo = k-1, hi = ceiling
        while lo < hi {
            let mid = lo + (hi-lo+1)/2
            if try choose(UInt64(mid),UInt64(k)) <= remaining { lo = mid } else { hi = mid-1 }
        }
        result[k-1] = lo
        remaining -= try choose(UInt64(lo),UInt64(k))
        ceiling = lo-1
    }
    return (result[0],result[1],result[2])
}
