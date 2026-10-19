import LogicKernelCore

public struct SystemVerilogSyntaxLimits: Sendable {
    public let nodes: Int
    public let children: Int
    public let symbols: Int
    public let nesting: Int
    public init(nodes: Int, children: Int, symbols: Int, nesting: Int) throws(LogicKernelError) {
        guard nodes > 0, children > 0, symbols > 0, nesting > 0 else {
            throw .invalidInput("Syntax capacities must be positive")
        }
        self.nodes = nodes; self.children = children; self.symbols = symbols; self.nesting = nesting
    }
}
