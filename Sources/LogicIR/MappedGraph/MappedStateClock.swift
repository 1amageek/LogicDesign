/// A flip-flop's physical clock binding and independently derived logical lineage.
public struct MappedStateClock: Sendable, Equatable {
    public let instance: MappedInstanceIndex
    public let carrier: MappedNetIndex
    public let risingEdge: Bool
    public let lineage: MappedClockLineage

    internal init(instance: MappedInstanceIndex, carrier: MappedNetIndex,
                  risingEdge: Bool, lineage: MappedClockLineage) {
        self.instance = instance; self.carrier = carrier
        self.risingEdge = risingEdge; self.lineage = lineage
    }
}
