public struct LogicKernelUsage: Sendable, Equatable {
    public let counters: [LogicResource: UInt64]
    public let peakManagedStorageBytes: UInt64

    public subscript(_ resource: LogicResource) -> UInt64 {
        counters[resource, default: 0]
    }
}
