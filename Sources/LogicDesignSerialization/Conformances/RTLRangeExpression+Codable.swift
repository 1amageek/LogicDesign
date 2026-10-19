import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension RTLRangeExpression: Codable {
    private enum CodingKeys: String, CodingKey { case `msb`, `lsb` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let msb = try container.decode(RTLExpression.self, forKey: .`msb`)
        let lsb = try container.decode(RTLExpression.self, forKey: .`lsb`)
        self.init(msb: msb, lsb: lsb)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(msb, forKey: .`msb`)
        try container.encode(lsb, forKey: .`lsb`)
    }
}
