public struct RTLProcessEvent: Sendable, Hashable {
    public var signal: String
    public var edge: RTLClockEdge?

    public init(signal: String, edge: RTLClockEdge? = nil) {
        self.signal = signal
        self.edge = edge
    }
}
