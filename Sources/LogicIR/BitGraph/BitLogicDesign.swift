public struct BitLogicDesign: Sendable {
    public static let schemaVersion = 1
    internal final class Storage: Sendable {
        let nodes: [BitLogicNode]
        let operands: [BitNodeIndex]
        let ports: [BitLogicPort]
        let portBits: [BitNodeIndex]
        let states: [BitLogicState]
        let order: [BitNodeIndex]
        init(nodes: consuming [BitLogicNode], operands: consuming [BitNodeIndex],
             ports: consuming [BitLogicPort], portBits: consuming [BitNodeIndex],
             states: consuming [BitLogicState], order: consuming [BitNodeIndex]) {
            self.nodes = nodes; self.operands = operands; self.ports = ports
            self.portBits = portBits; self.states = states; self.order = order
        }
    }
    internal let storage: Storage
    internal init(storage: Storage) { self.storage = storage }
    public var nodeCount: Int { storage.nodes.count }
    public var operandCount: Int { storage.operands.count }
    public var portCount: Int { storage.ports.count }
    public var portBitCount: Int { storage.portBits.count }
    public var stateCount: Int { storage.states.count }

    @available(macOS 26.0, *)
    public borrowing func withNodes<Result, Failure: Error>(_ body: (borrowing Span<BitLogicNode>) throws(Failure) -> Result) throws(Failure) -> Result {
        let owner = storage; let nodes = owner.nodes
        defer { withExtendedLifetime(owner) {} }
        return try body(nodes.isEmpty ? Span() : nodes.span)
    }

    @available(macOS 26.0, *)
    public borrowing func withTables<Result, Failure: Error>(
        _ body: (borrowing Span<BitLogicNode>, borrowing Span<BitNodeIndex>,
                 borrowing Span<BitLogicPort>, borrowing Span<BitNodeIndex>,
                 borrowing Span<BitLogicState>, borrowing Span<BitNodeIndex>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage
        let nodes = owner.nodes; let operands = owner.operands; let ports = owner.ports
        let bits = owner.portBits; let states = owner.states; let order = owner.order
        defer { withExtendedLifetime(owner) {} }
        // Empty Array storage is not necessarily aligned for Element on WASM.
        return try body(nodes.isEmpty ? Span() : nodes.span,
                        operands.isEmpty ? Span() : operands.span,
                        ports.isEmpty ? Span() : ports.span,
                        bits.isEmpty ? Span() : bits.span,
                        states.isEmpty ? Span() : states.span,
                        order.isEmpty ? Span() : order.span)
    }
}
