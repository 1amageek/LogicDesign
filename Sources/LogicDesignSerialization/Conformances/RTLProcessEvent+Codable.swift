import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension RTLProcessEvent: Codable {
    private enum CodingKeys: String, CodingKey { case `signal`, `edge` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let signal = try container.decode(String.self, forKey: .`signal`)
        let edge = try container.decodeIfPresent(RTLClockEdge.self, forKey: .`edge`)
        self.init(signal: signal, edge: edge)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(signal, forKey: .`signal`)
        try container.encodeIfPresent(edge, forKey: .`edge`)
    }
}
