import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicDesignSnapshot: Codable {
    private enum CodingKeys: String, CodingKey { case `schemaVersion`, `rtl`, `gate`, `designDigest` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .`schemaVersion`)
        let rtl = try container.decode(RTLDesign.self, forKey: .`rtl`)
        let gate = try container.decodeIfPresent(GateDesign.self, forKey: .`gate`)
        let designDigest = try container.decodeIfPresent(String.self, forKey: .`designDigest`)
        self.init(rtl: rtl, gate: gate, designDigest: designDigest, schemaVersion: schemaVersion)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .`schemaVersion`)
        try container.encode(rtl, forKey: .`rtl`)
        try container.encodeIfPresent(gate, forKey: .`gate`)
        try container.encodeIfPresent(designDigest, forKey: .`designDigest`)
    }
}
