import Foundation
import LogicIR

public struct SystemVerilogSourceUnit: Sendable, Hashable, Codable {
    public var path: String
    public var source: String

    public init(path: String, source: String) {
        self.path = path
        self.source = source
    }

    public var file: LogicSourceFile {
        let data = Data(source.utf8)
        let digest = LogicSourceDigest.sha256HexadecimalValue(of: data)
        return LogicSourceFile(
            path: path,
            sha256: digest,
            byteCount: Int64(data.count)
        )
    }
}
