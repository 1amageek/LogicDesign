import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicSourceFile: Codable {
    private enum CodingKeys: String, CodingKey { case `path`, `sha256`, `byteCount` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let path = try container.decode(String.self, forKey: .`path`)
        let sha256 = try container.decode(String.self, forKey: .`sha256`)
        let byteCount = try container.decode(Int64.self, forKey: .`byteCount`)
        self.init(path: path, sha256: sha256, byteCount: byteCount)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .`path`)
        try container.encode(sha256, forKey: .`sha256`)
        try container.encode(byteCount, forKey: .`byteCount`)
    }
}
