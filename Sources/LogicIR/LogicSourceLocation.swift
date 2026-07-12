import Foundation

public struct LogicSourceLocation: Sendable, Hashable, Codable {
    public var path: String
    public var line: Int
    public var column: Int
    public var offset: Int

    public init(path: String, line: Int, column: Int, offset: Int) {
        self.path = path
        self.line = line
        self.column = column
        self.offset = offset
    }
}
