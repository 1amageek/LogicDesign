import Foundation

public struct RTLAssignment: Sendable, Hashable, Codable {
    public var id: String
    public var target: RTLExpression
    public var value: RTLExpression
    public var nonBlocking: Bool
    public var source: LogicSourceSpan?

    public init(
        id: String,
        target: RTLExpression,
        value: RTLExpression,
        nonBlocking: Bool = false,
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.target = target
        self.value = value
        self.nonBlocking = nonBlocking
        self.source = source
    }
}
