public enum MappedEvaluationStep: Sendable, Equatable {
    case net(MappedNetIndex)
    case state(MappedInstanceIndex)
}
