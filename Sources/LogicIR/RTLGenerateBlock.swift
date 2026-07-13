import Foundation

public struct RTLGenerateBlock: Sendable, Hashable, Codable {
    public var id: String
    public var label: String
    public var kind: RTLGenerateKind
    public var condition: RTLExpression?
    public var loopVariable: String
    public var start: Int64
    public var limit: Int64
    public var step: Int64
    public var startExpression: RTLExpression?
    public var limitExpression: RTLExpression?
    public var stepExpression: RTLExpression?
    public var instances: [RTLInstance]
    public var assignments: [RTLAssignment]
    public var source: LogicSourceSpan?

    public init(
        id: String,
        label: String,
        kind: RTLGenerateKind = .forLoop,
        condition: RTLExpression? = nil,
        loopVariable: String,
        start: Int64,
        limit: Int64,
        step: Int64 = 1,
        startExpression: RTLExpression? = nil,
        limitExpression: RTLExpression? = nil,
        stepExpression: RTLExpression? = nil,
        instances: [RTLInstance] = [],
        assignments: [RTLAssignment] = [],
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.condition = condition
        self.loopVariable = loopVariable
        self.start = start
        self.limit = limit
        self.step = step
        self.startExpression = startExpression
        self.limitExpression = limitExpression
        self.stepExpression = stepExpression
        self.instances = instances
        self.assignments = assignments
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case kind
        case condition
        case loopVariable
        case start
        case limit
        case step
        case startExpression
        case limitExpression
        case stepExpression
        case instances
        case assignments
        case source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        kind = try container.decodeIfPresent(RTLGenerateKind.self, forKey: .kind) ?? .forLoop
        condition = try container.decodeIfPresent(RTLExpression.self, forKey: .condition)
        loopVariable = try container.decode(String.self, forKey: .loopVariable)
        start = try container.decode(Int64.self, forKey: .start)
        limit = try container.decode(Int64.self, forKey: .limit)
        step = try container.decode(Int64.self, forKey: .step)
        startExpression = try container.decodeIfPresent(RTLExpression.self, forKey: .startExpression)
        limitExpression = try container.decodeIfPresent(RTLExpression.self, forKey: .limitExpression)
        stepExpression = try container.decodeIfPresent(RTLExpression.self, forKey: .stepExpression)
        instances = try container.decode([RTLInstance].self, forKey: .instances)
        assignments = try container.decode([RTLAssignment].self, forKey: .assignments)
        source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .source)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(condition, forKey: .condition)
        try container.encode(loopVariable, forKey: .loopVariable)
        try container.encode(start, forKey: .start)
        try container.encode(limit, forKey: .limit)
        try container.encode(step, forKey: .step)
        try container.encodeIfPresent(startExpression, forKey: .startExpression)
        try container.encodeIfPresent(limitExpression, forKey: .limitExpression)
        try container.encodeIfPresent(stepExpression, forKey: .stepExpression)
        try container.encode(instances, forKey: .instances)
        try container.encode(assignments, forKey: .assignments)
        try container.encodeIfPresent(source, forKey: .source)
    }
}
