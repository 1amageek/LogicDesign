import Foundation
import LogicIR
import CircuiteFoundation

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
        let digest: String
        do {
            digest = try SHA256ContentDigester().digest(data: data).hexadecimalValue
        } catch {
            preconditionFailure("Unable to digest power-intent source: \(error)")
        }
        return LogicSourceFile(
            path: path,
            sha256: digest,
            byteCount: Int64(data.count)
        )
    }
}
