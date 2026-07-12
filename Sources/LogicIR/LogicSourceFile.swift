import Foundation

public struct LogicSourceFile: Sendable, Hashable, Codable {
    public var path: String
    public var sha256: String
    public var byteCount: Int64

    public init(path: String, sha256: String, byteCount: Int64) {
        self.path = path
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}
