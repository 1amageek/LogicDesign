public struct WordReset: Sendable, Equatable {
    public let signal: WordNodeIndex
    public let activeHigh: Bool
    public let value: LogicFourStateVector
    public let kind: BitReset.Kind
    public init(signal: WordNodeIndex, activeHigh: Bool, value: LogicFourStateVector, kind: BitReset.Kind) {
        self.signal = signal; self.activeHigh = activeHigh; self.value = value; self.kind = kind
    }
}
