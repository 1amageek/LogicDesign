import Foundation

public struct GateCell: Sendable, Hashable, Codable {
    public var id: String
    public var type: String
    public var instanceName: String
    public var pins: [GatePin]
    public var parameters: [GateCellParameter]
    public var source: LogicSourceSpan?

    public init(
        id: String,
        type: String,
        instanceName: String,
        pins: [GatePin] = [],
        parameters: [GateCellParameter] = [],
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.type = type
        self.instanceName = instanceName
        self.pins = pins
        self.parameters = parameters
        self.source = source
    }

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
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        instanceName = try container.decode(String.self, forKey: .instanceName)
        pins = try container.decodeIfPresent([GatePin].self, forKey: .pins) ?? []
        parameters = try container.decodeIfPresent(
            [GateCellParameter].self,
            forKey: .parameters
        ) ?? []
        source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .source)
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
