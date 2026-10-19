/// Clock identity derived from validated actual-cell functions and connectivity.
public enum MappedClockLineage: Sendable, Equatable {
    case primaryInput(root: MappedNetIndex, inverted: Bool, risingEdge: Bool)
    case opaque(carrier: MappedNetIndex, risingEdge: Bool)
}
