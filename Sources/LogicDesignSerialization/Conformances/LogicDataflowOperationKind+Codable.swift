import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicDataflowOperationKind: Codable {
    private enum CodingKeys: String, CodingKey { case `rawValue` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(String.self, forKey: .`rawValue`)
        guard let value = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid operation identifier"))
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue, forKey: .`rawValue`)
    }
}
