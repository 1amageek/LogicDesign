import LogicIR
import LogicKernelCore

package struct SystemVerilogSyntaxTree: Sendable {
    private final class Storage: Sendable {
        let nodes: [SystemVerilogSyntaxNode]
        let children: [Int]
        let symbols: [Range<Int>]
        init(nodes: consuming [SystemVerilogSyntaxNode], children: consuming [Int], symbols: consuming [Range<Int>]) {
            self.nodes = nodes; self.children = children; self.symbols = symbols
        }
    }
    package let source: SystemVerilogSourceText
    package let modules: Range<Int>
    private let storage: Storage
    package var nodeCount: Int { storage.nodes.count }
    package var symbolCount: Int { storage.symbols.count }
    internal init(source: SystemVerilogSourceText, nodes: consuming [SystemVerilogSyntaxNode],
                  children: consuming [Int], symbols: consuming [Range<Int>], modules: Range<Int>) {
        self.source = source; self.modules = modules
        storage = Storage(nodes: nodes, children: children, symbols: symbols)
    }
    package borrowing func node(at index: Int) throws(LogicKernelError) -> SystemVerilogSyntaxNode {
        guard storage.nodes.indices.contains(index) else { throw .invalidInput("Syntax node index outside tree") }
        return storage.nodes[index]
    }
    package borrowing func child(at index: Int) throws(LogicKernelError) -> Int {
        guard storage.children.indices.contains(index) else { throw .invalidInput("Syntax child index outside tree") }
        return storage.children[index]
    }
    package borrowing func symbolRange(at index: Int) throws(LogicKernelError) -> Range<Int> {
        guard storage.symbols.indices.contains(index) else { throw .invalidInput("Syntax symbol index outside tree") }
        return storage.symbols[index]
    }
    @available(macOS 26.0, *)
    package borrowing func withTables<Result, Failure: Error>(
        _ body: (borrowing Span<SystemVerilogSyntaxNode>, borrowing Span<Int>, borrowing Span<Range<Int>>)
            throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage; let nodes = owner.nodes; let children = owner.children; let symbols = owner.symbols
        defer { withExtendedLifetime(owner) {} }
        return try body(nodes.isEmpty ? Span() : nodes.span, children.isEmpty ? Span() : children.span,
                        symbols.isEmpty ? Span() : symbols.span)
    }
}
