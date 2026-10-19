public struct BitReset: Sendable, Equatable {
    public enum Kind: Sendable { case synchronous, asynchronous }
    public let signal: BitNodeIndex
    public let activeHigh: Bool
    public let value: Bool
    public let kind: Kind

    public init(signal: BitNodeIndex, activeHigh: Bool, value: Bool, kind: Kind) {
        self.signal = signal
        self.activeHigh = activeHigh
        self.value = value
        self.kind = kind
    }
}
