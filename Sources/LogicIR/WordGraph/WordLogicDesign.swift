public struct WordLogicDesign: Sendable {
    public static let schemaVersion = 1
    internal final class Storage: Sendable {
        let nodes: [WordLogicNode]
        let operands: [WordNodeIndex]
        let ports: [WordLogicPort]
        let states: [WordLogicState]
        let order: [WordNodeIndex]
        init(nodes: consuming [WordLogicNode], operands: consuming [WordNodeIndex],
             ports: consuming [WordLogicPort], states: consuming [WordLogicState], order: consuming [WordNodeIndex]) {
            self.nodes = nodes; self.operands = operands; self.ports = ports
            self.states = states; self.order = order
        }
    }
    internal let storage: Storage
    internal init(storage: Storage) { self.storage = storage }
    public var nodeCount: Int { storage.nodes.count }
    public var operandCount: Int { storage.operands.count }
    public var portCount: Int { storage.ports.count }
    public var stateCount: Int { storage.states.count }

    @available(macOS 26.0, *)
    public borrowing func withNodes<Result, Failure: Error>(
        _ body: (borrowing Span<WordLogicNode>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage; let nodes = owner.nodes
        defer { withExtendedLifetime(owner) {} }
        return try body(nodes.isEmpty ? Span() : nodes.span)
    }

    @available(macOS 26.0, *)
    public borrowing func withTables<Result, Failure: Error>(
        _ body: (borrowing Span<WordLogicNode>, borrowing Span<WordNodeIndex>, borrowing Span<WordLogicPort>,
                 borrowing Span<WordLogicState>, borrowing Span<WordNodeIndex>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage
        let nodes = owner.nodes; let operands = owner.operands; let ports = owner.ports
        let states = owner.states; let order = owner.order
        defer { withExtendedLifetime(owner) {} }
        return try body(nodes.isEmpty ? Span() : nodes.span, operands.isEmpty ? Span() : operands.span,
                        ports.isEmpty ? Span() : ports.span, states.isEmpty ? Span() : states.span,
                        order.isEmpty ? Span() : order.span)
    }
}
