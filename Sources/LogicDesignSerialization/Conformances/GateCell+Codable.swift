import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension GateCell: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case instanceName
        case pins
        case parameters
        case source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let type = try container.decode(String.self, forKey: .type)
        let instanceName = try container.decode(String.self, forKey: .instanceName)
        let pins = try container.decodeIfPresent([GatePin].self, forKey: .pins) ?? []
        let parameters = try container.decodeIfPresent(
            [GateCellParameter].self,
            forKey: .parameters
        ) ?? []
        let source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .source)
        self.init(id: id, type: type, instanceName: instanceName, pins: pins, parameters: parameters, source: source)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(instanceName, forKey: .instanceName)
        try container.encode(pins, forKey: .pins)
        if !parameters.isEmpty {
            try container.encode(parameters, forKey: .parameters)
        }
        try container.encodeIfPresent(source, forKey: .source)
    }
}
