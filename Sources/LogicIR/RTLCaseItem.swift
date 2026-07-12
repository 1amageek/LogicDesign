import Foundation

public struct RTLCaseItem: Sendable, Hashable, Codable {
    public var matches: [RTLExpression]
    public var statements: [RTLStatement]
    public var source: LogicSourceSpan?

    public init(
        matches: [RTLExpression],
        statements: [RTLStatement],
        source: LogicSourceSpan? = nil
    ) {
        self.matches = matches
        self.statements = statements
        self.source = source
    }
}
