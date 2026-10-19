public struct LogicKernelLimits: Sendable, Equatable {
    private let maximums: [LogicResource: UInt64]

    public init(maximums: [LogicResource: UInt64]) throws(LogicKernelError) {
        for resource in LogicResource.allCases {
            guard let maximum = maximums[resource], maximum > 0 else {
                throw .invalidInput("Every resource requires an explicit positive limit")
            }
        }
        self.maximums = maximums
    }

    public subscript(_ resource: LogicResource) -> UInt64 {
        // Construction establishes a complete resource table.
        maximums[resource]!
    }
}
