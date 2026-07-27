public enum LogicDataflowChannelStrictness: String, Sendable, Hashable, Codable {
    case provenMutuallyExclusive
    case totalOrder
    case runtimeOrdered
    case arbitraryStaticOrder
}
