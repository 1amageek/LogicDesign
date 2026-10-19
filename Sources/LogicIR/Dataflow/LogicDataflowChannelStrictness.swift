public enum LogicDataflowChannelStrictness: String, Sendable, Hashable {
    case provenMutuallyExclusive
    case totalOrder
    case runtimeOrdered
    case arbitraryStaticOrder
}
