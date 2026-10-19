public enum WordLogicOperation: Sendable, Equatable {
    case input
    case state(WordStateIndex)
    case constant(LogicFourStateVector)
    case compute(WordLogicOpcode)
}
