public enum BitOperation: Sendable, Equatable {
    case input
    case constant(Bool)
    case state(BitStateIndex)
    case buffer, invert, and, or, xor, select

    public var operandCount: Int {
        switch self {
        case .input, .constant, .state: 0
        case .buffer, .invert: 1
        case .and, .or, .xor: 2
        case .select: 3
        }
    }
}
