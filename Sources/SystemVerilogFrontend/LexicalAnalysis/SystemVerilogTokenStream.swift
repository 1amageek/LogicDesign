import LogicIR
import LogicKernelCore

public struct SystemVerilogTokenStream: Sendable {
    private final class Storage: Sendable {
        let tokens: [SystemVerilogLexicalToken]
        init(tokens: consuming [SystemVerilogLexicalToken]) { self.tokens = tokens }
    }
    public let source: SystemVerilogSourceText
    private let storage: Storage
    public var count: Int { storage.tokens.count }
    internal init(source: SystemVerilogSourceText, tokens: consuming [SystemVerilogLexicalToken]) {
        self.source = source; storage = Storage(tokens: tokens)
    }
    internal borrowing func token(at index: Int) throws(LogicKernelError) -> SystemVerilogLexicalToken {
        guard storage.tokens.indices.contains(index) else { throw .invalidInput("Token index outside stream") }
        return storage.tokens[index]
    }
    @available(macOS 26.0, *)
    public borrowing func withTokens<Result, Failure: Error>(
        _ body: (borrowing Span<SystemVerilogLexicalToken>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage; let tokens = owner.tokens
        defer { withExtendedLifetime(owner) {} }
        return try body(tokens.span)
    }
}
