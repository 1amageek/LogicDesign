import CircuiteFoundation

/// Caller-supplied interchange spelling; construction grants no identity or proof authority.
public struct MappedGateVerilogNaming: Sendable, Hashable {
    public let instanceNames: [DesignEntityID: String]
    public let netNames: [DesignEntityID: String]
    public let portBitNames: [DesignEntityID: [String]]

    public init(instanceNames: [DesignEntityID: String], netNames: [DesignEntityID: String],
                portBitNames: [DesignEntityID: [String]]) {
        self.instanceNames = instanceNames; self.netNames = netNames; self.portBitNames = portBitNames
    }
}
