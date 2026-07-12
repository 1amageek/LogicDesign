import Foundation
import LogicIR
import XcircuitePackage

public struct SystemVerilogSourceUnit: Sendable, Hashable, Codable {
    public var path: String
    public var source: String

    public init(path: String, source: String) {
        self.path = path
        self.source = source
    }

    public var file: LogicSourceFile {
        let data = Data(source.utf8)
        return LogicSourceFile(
            path: path,
            sha256: XcircuiteHasher().sha256(data: data),
            byteCount: Int64(data.count)
        )
    }
}
