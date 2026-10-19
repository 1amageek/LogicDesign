public struct RTLResolvedReset: Sendable {
    public let signal: RTLExpressionIndex
    public let activeHigh: Bool
    public init(signal: RTLExpressionIndex, activeHigh: Bool) { self.signal = signal; self.activeHigh = activeHigh }
}
