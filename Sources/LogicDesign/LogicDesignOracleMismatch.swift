import Foundation

public struct LogicDesignOracleMismatch: Sendable, Hashable, Codable {
    public var field: String
    public var expected: String?
    public var actual: String?

    public init(field: String, expected: String?, actual: String?) {
        self.field = field
        self.expected = expected
        self.actual = actual
    }
}
