public enum LogicDataflowFlopKind: String, Sendable, Hashable, Codable {
    case none
    case flop
    case skid
    case zeroLatency
}
