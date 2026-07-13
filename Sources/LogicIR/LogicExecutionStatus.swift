import Foundation

/// Execution outcome owned by the logic-design domain.
public enum LogicExecutionStatus: String, Sendable, Hashable, Codable {
    case completed
    case failed
    case blocked
    case cancelled
}
