public enum WordLogicOpcode: Sendable, Equatable {
    case bitcast, zeroExtend, signExtend
    case invert, negate
    case and, or, xor
    case add, subtract, multiply
    case equal, lessThan
    case logicalNot, logicalAnd, logicalOr
    case reduceAnd, reduceOr, reduceXor
    case shiftLeft, shiftRight(arithmetic: Bool)
    case select, concatenate, slice(offset: Int)

    public var fixedOperandCount: Int? {
        switch self {
        case .bitcast, .zeroExtend, .signExtend, .invert, .negate, .logicalNot,
             .reduceAnd, .reduceOr, .reduceXor, .slice: 1
        case .and, .or, .xor, .add, .subtract, .multiply, .equal, .lessThan,
             .logicalAnd, .logicalOr, .shiftLeft, .shiftRight: 2
        case .select: 3
        case .concatenate: nil
        }
    }
}
