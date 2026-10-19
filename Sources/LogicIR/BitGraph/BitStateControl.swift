public enum BitStateControl: Sendable, Equatable {
    public enum Edge: Sendable { case rising, falling }
    case flipFlop(clock: BitNodeIndex, edge: Edge, enable: BitNodeIndex?, reset: BitReset?)
    case latch(gate: BitNodeIndex, activeHigh: Bool, reset: BitReset?)
}
