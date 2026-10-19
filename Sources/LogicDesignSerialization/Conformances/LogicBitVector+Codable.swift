import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicBitVector: Codable {
    private enum CodingKeys: String, CodingKey { case `width`, `bytes` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let width = try container.decode(Int.self, forKey: .`width`)
        let bytes = try container.decode([UInt8].self, forKey: .`bytes`)
        try self.init(width: width, bytes: bytes)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .`width`)
        try container.encode(bytes, forKey: .`bytes`)
    }
}
