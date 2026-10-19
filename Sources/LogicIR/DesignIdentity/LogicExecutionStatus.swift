/// Execution outcome owned by the logic-design domain.
public enum LogicExecutionStatus: String, Sendable, Hashable {
    case completed
    case failed
    case blocked
    case cancelled
}
