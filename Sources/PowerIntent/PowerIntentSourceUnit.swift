import Foundation
import LogicIR

public struct PowerIntentSourceUnit: Sendable, Hashable, Codable {
    public var path: String
    public var source: String
    public var format: PowerIntentFormat

    public init(path: String, source: String, format: PowerIntentFormat) {
        self.path = path
        self.source = source
        self.format = format
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
