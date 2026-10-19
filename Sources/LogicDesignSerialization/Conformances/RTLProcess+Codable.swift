import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension RTLProcess: Codable {
    private enum CodingKeys: String, CodingKey { case `id`, `kind`, `sensitivity`, `clockEdge`, `events`, `statements`, `source` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .`id`)
        let kind = try container.decode(RTLProcessKind.self, forKey: .`kind`)
        let sensitivity = try container.decode([String].self, forKey: .`sensitivity`)
        let clockEdge = try container.decodeIfPresent(RTLClockEdge.self, forKey: .`clockEdge`)
        let events = try container.decode([RTLProcessEvent].self, forKey: .`events`)
        let statements = try container.decode([RTLStatement].self, forKey: .`statements`)
        let source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .`source`)
        self.init(id: id, kind: kind, sensitivity: sensitivity, clockEdge: clockEdge, events: events, statements: statements, source: source)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .`id`)
        try container.encode(kind, forKey: .`kind`)
        try container.encode(sensitivity, forKey: .`sensitivity`)
        try container.encodeIfPresent(clockEdge, forKey: .`clockEdge`)
        try container.encode(events, forKey: .`events`)
        try container.encode(statements, forKey: .`statements`)
        try container.encodeIfPresent(source, forKey: .`source`)
    }
}
