import Foundation

public enum GenerationState: String, Codable, Sendable { case idle, prepared, presenting, accepted, persisting, advancing, cancelled, failed }
/// Pure callback reducer. The host must report actual dismissal, not merely request it.
public struct GenerationCoordinator: Sendable {
    public private(set) var state: GenerationState = .idle
    public private(set) var sessionID: UUID?
    public private(set) var completed = 0
    private var dismissed = true
    private var persisted = false
    private var stopped = false
    public init() {}
    @discardableResult public mutating func prepare(id: UUID = UUID()) -> Bool {
        guard dismissed, [.idle,.prepared,.advancing,.failed,.cancelled].contains(state) else { return false }
        sessionID=id; state = .prepared; persisted=false; stopped=false
        return true
    }
    public mutating func present(_ id: UUID) -> Bool {
        guard id==sessionID, state == .prepared, dismissed, !stopped else { return false }
        state = .presenting; dismissed=false; return true
    }
    public mutating func accept(_ id: UUID) -> Bool {
        guard id==sessionID, state == .presenting else { return false }
        state = .accepted; return true
    }
    public mutating func beginPersistence(_ id: UUID) -> Bool {
        guard id==sessionID, state == .accepted else { return false }
        state = .persisting; return true
    }
    public mutating func didPersist(_ id: UUID) -> Bool {
        guard id==sessionID, state == .persisting, !persisted else { return false }
        persisted=true; completed += 1; return true
    }
    public mutating func didDismiss(_ id: UUID) {
        guard id==sessionID else { return }
        dismissed=true
        if state == .presenting || state == .cancelled {
            state = .prepared
            sessionID=UUID() // A retry is a new presentation; late callbacks from the dismissed sheet are stale.
        }
    }
    public mutating func cancel(_ id: UUID) {
        guard id==sessionID, state == .presenting else { return }
        state = dismissed ? .prepared : .cancelled
    }
    public mutating func fail(_ id: UUID) {
        guard id==sessionID, state != .advancing, !persisted else { return }
        state = .failed
    }
    public mutating func stop() { stopped=true }
    public mutating func advance(_ id: UUID, autoAdvance: Bool, limit: Int?, foreground: Bool) -> Bool {
        guard id==sessionID, persisted, dismissed, state == .persisting, !stopped, foreground,
              autoAdvance, limit.map({ completed < $0 }) ?? true else { return false }
        state = .advancing; return true
    }
    public mutating func finishWithoutAdvancing(_ id: UUID) -> Bool {
        guard id==sessionID, state == .persisting, persisted, dismissed else { return false }
        state = .idle; return true
    }
}
