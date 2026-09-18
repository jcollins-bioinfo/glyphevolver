import Foundation

public enum GenerationFeedback: Int, Codable, CaseIterable, Sendable { case poor = -1, neutral = 0, good = 1, favorite = 2 }
public enum BehavioralSignal: String, Codable, Sendable { case branchedFrom, continuedFrom, favorited, copied, shared, deletedSoonAfterCreation }
public struct PreferenceExample: Codable, Sendable {
    public let nodeID: UUID
    public let features: [Double]
    public let feedback: GenerationFeedback
    public init(nodeID: UUID = UUID(), features: [Double], feedback: GenerationFeedback) {
        self.nodeID=nodeID; self.features=features; self.feedback=feedback
    }
}
public struct PreferenceModel: Codable, Sendable {
    public static let version = "logistic-1"
    public static let featureSchema = "quality11-template7-v1"
    public private(set) var schema = Self.featureSchema
    public private(set) var coefficients = [Double](repeating:0,count:18)
    public private(set) var bias = 0.0
    public private(set) var trainingSampleCount = 0
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func validateSchema() {
        if schema != Self.featureSchema || coefficients.count != 18 || !coefficients.allSatisfy(\.isFinite) || !bias.isFinite { reset() }
    }
    public func predict(_ features: [Double]) -> Double? {
        guard schema == Self.featureSchema, trainingSampleCount >= 12, features.count==coefficients.count,
              features.allSatisfy(\.isFinite), coefficients.allSatisfy(\.isFinite), bias.isFinite else { return nil }
        return sigmoid(zip(features,coefficients).map(*).reduce(bias,+))
    }
    /// Rebuild from current explicit labels, avoiding double training when a rating is edited.
    public mutating func train(_ examples: [PreferenceExample]) {
        reset()
        var unique: [UUID:PreferenceExample] = [:]
        for e in examples { unique[e.nodeID]=e }
        let valid = unique.values.filter { $0.feedback != .neutral && $0.features.count==18 && $0.features.allSatisfy { $0.isFinite && (0...1).contains($0) } }
            .sorted { $0.nodeID.uuidString < $1.nodeID.uuidString }
        trainingSampleCount = valid.count
        guard valid.count >= 12 else { return }
        for _ in 0..<20 {
            for example in valid {
                let p = sigmoid(zip(example.features,coefficients).map(*).reduce(bias,+))
                let error = p - (example.feedback == .poor ? 0 : 1)
                for i in coefficients.indices { coefficients[i] -= 0.05*(error*example.features[i]+0.02*coefficients[i]) }
                bias -= 0.05*error
            }
        }
    }
    private func sigmoid(_ z: Double) -> Double {
        if z >= 0 { return 1/(1+exp(-z)) }
        let e = exp(z); return e/(1+e)
    }
}
