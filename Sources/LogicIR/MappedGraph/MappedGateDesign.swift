import LogicKernelCore

public struct MappedGateDesign: Sendable {
    public static let schemaVersion = 1
    internal final class Storage: Sendable {
        let library: LogicTechnologyLibrary
        let nets: [MappedGateNet]
        let instances: [MappedGateInstance]
        let pins: [MappedNetIndex]
        let ports: [MappedGatePort]
        let bits: [MappedNetIndex]
        let order: [MappedEvaluationStep]
        let clocks: [MappedStateClock]
        let stateCount: Int
        init(library: LogicTechnologyLibrary, nets: consuming [MappedGateNet], instances: consuming [MappedGateInstance],
             pins: consuming [MappedNetIndex], ports: consuming [MappedGatePort], bits: consuming [MappedNetIndex],
             order: consuming [MappedEvaluationStep], clocks: consuming [MappedStateClock], stateCount: Int) {
            self.library = library; self.nets = nets; self.instances = instances; self.pins = pins
            self.ports = ports; self.bits = bits; self.order = order; self.clocks = clocks; self.stateCount = stateCount
        }
    }
    internal let storage: Storage
    internal init(storage: Storage) { self.storage = storage }
    public var library: LogicTechnologyLibrary { storage.library }
    public var netCount: Int { storage.nets.count }
    public var instanceCount: Int { storage.instances.count }
    public var pinConnectionCount: Int { storage.pins.count }
    public var portCount: Int { storage.ports.count }
    public var portBitCount: Int { storage.bits.count }
    public var stateCount: Int { storage.stateCount }

    @available(macOS 26.0, *)
    public borrowing func withStateClocks<Result, Failure: Error>(
        _ body: (borrowing Span<MappedStateClock>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage
        let clocks = owner.clocks
        defer { withExtendedLifetime(owner) {} }
        return try body(clocks.isEmpty ? Span() : clocks.span)
    }

    @available(macOS 26.0, *)
    public borrowing func withTables<Result, Failure: Error>(
        _ body: (borrowing Span<MappedGateNet>, borrowing Span<MappedGateInstance>, borrowing Span<MappedNetIndex>,
                 borrowing Span<MappedGatePort>, borrowing Span<MappedNetIndex>, borrowing Span<MappedEvaluationStep>)
            throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage
        let nets = owner.nets; let instances = owner.instances; let pins = owner.pins
        let ports = owner.ports; let bits = owner.bits; let order = owner.order
        defer { withExtendedLifetime(owner) {} }
        return try body(nets.isEmpty ? Span() : nets.span, instances.isEmpty ? Span() : instances.span,
                        pins.isEmpty ? Span() : pins.span, ports.isEmpty ? Span() : ports.span,
                        bits.isEmpty ? Span() : bits.span, order.isEmpty ? Span() : order.span)
    }
}
