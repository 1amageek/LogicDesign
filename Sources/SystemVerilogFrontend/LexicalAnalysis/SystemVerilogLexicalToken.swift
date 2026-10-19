public struct SystemVerilogLexicalToken: Sendable, Equatable {
    public enum Kind: Sendable {
        case identifier, escapedIdentifier, number, string, punctuation, `operator`, endOfFile
    }
    public let kind: Kind
    public let byteRange: Range<Int>
    internal init(kind: Kind, byteRange: Range<Int>) { self.kind = kind; self.byteRange = byteRange }
}
