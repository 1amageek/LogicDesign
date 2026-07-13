import Foundation
import LogicIR
import CircuiteFoundation

public struct SystemVerilogSourceUnit: Sendable, Hashable, Codable {
    public var path: String
    public var source: String

    public init(path: String, source: String) {
        self.path = path
        self.source = source
    }

    public var file: LogicSourceFile {
        let data = Data(source.utf8)
        let digest: String
        do {
            digest = try SHA256ContentDigester().digest(data: data).hexadecimalValue
        } catch {
            preconditionFailure("Unable to digest SystemVerilog source: \(error)")
        }
        return LogicSourceFile(
            path: path,
            sha256: digest,
            byteCount: Int64(data.count)
        )
    }
}
