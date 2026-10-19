import LogicIR

public enum SystemVerilogSynthesisLiteral: Sendable, Equatable {
    case integer(value: LogicFourStateVector, isSigned: Bool, isUnsized: Bool)
    case fill(Bool)
}
