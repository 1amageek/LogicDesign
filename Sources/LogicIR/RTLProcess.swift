import Foundation

public struct RTLProcess: Sendable, Hashable, Codable {
    public var id: String
    public var kind: RTLProcessKind
    public var sensitivity: [String]
    public var clockEdge: RTLClockEdge?
    public var events: [RTLProcessEvent]
    public var statements: [RTLStatement]
    public var source: LogicSourceSpan?

    public init(
        id: String,
        kind: RTLProcessKind,
        sensitivity: [String] = [],
        clockEdge: RTLClockEdge? = nil,
        events: [RTLProcessEvent] = [],
        statements: [RTLStatement] = [],
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sensitivity = sensitivity
        self.clockEdge = clockEdge
        self.events = events
        self.statements = statements
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case sensitivity
        case clockEdge
        case events
        case statements
        case source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(RTLProcessKind.self, forKey: .kind)
        sensitivity = try container.decode([String].self, forKey: .sensitivity)
        clockEdge = try container.decodeIfPresent(RTLClockEdge.self, forKey: .clockEdge)
        events = try container.decodeIfPresent([RTLProcessEvent].self, forKey: .events) ?? []
        statements = try container.decode([RTLStatement].self, forKey: .statements)
        source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .source)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(sensitivity, forKey: .sensitivity)
        try container.encodeIfPresent(clockEdge, forKey: .clockEdge)
        if !events.isEmpty {
            try container.encode(events, forKey: .events)
        }
        try container.encode(statements, forKey: .statements)
        try container.encodeIfPresent(source, forKey: .source)
    }
}
