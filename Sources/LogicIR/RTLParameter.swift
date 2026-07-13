import Foundation

public struct RTLParameter: Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    public var value: Int64
    public var defaultExpression: RTLExpression?
    public var source: LogicSourceSpan?

    public init(
        id: String,
        name: String,
        value: Int64,
        defaultExpression: RTLExpression? = nil,
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.defaultExpression = defaultExpression
        self.source = source
    }
}
