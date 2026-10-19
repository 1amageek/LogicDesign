public enum WordStateControl: Sendable, Equatable {
    case flipFlop(clock: WordNodeIndex, edge: BitStateControl.Edge, enable: WordNodeIndex?, reset: WordReset?)
    case latch(gate: WordNodeIndex, activeHigh: Bool, reset: WordReset?)
}
