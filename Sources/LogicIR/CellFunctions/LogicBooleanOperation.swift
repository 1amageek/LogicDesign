public enum LogicBooleanOperation: Sendable, Hashable {
    case constant(Bool)
    case input(Int)
    case invert(LogicBooleanNodeIndex)
    case and(LogicBooleanNodeIndex, LogicBooleanNodeIndex)
    case or(LogicBooleanNodeIndex, LogicBooleanNodeIndex)
    case xor(LogicBooleanNodeIndex, LogicBooleanNodeIndex)

    internal var operandCount: UInt64 {
        switch self {
        case .constant, .input: 0
        case .invert: 1
        case .and, .or, .xor: 2
        }
    }

    internal func isValid(nodeCount: Int, inputCount: Int) -> Bool {
        func contains(_ index: LogicBooleanNodeIndex) -> Bool {
            index.rawValue >= 0 && index.rawValue < nodeCount
        }
        switch self {
        case .constant: return true
        case .input(let slot): return slot >= 0 && slot < inputCount
        case .invert(let node): return contains(node)
        case .and(let a, let b), .or(let a, let b), .xor(let a, let b): return contains(a) && contains(b)
        }
    }
}
