import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension RTLGenerateBlock: Codable {
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
        let id = try container.decode(String.self, forKey: .id)
        let label = try container.decode(String.self, forKey: .label)
        let kind = try container.decode(RTLGenerateKind.self, forKey: .kind)
        let condition = try container.decodeIfPresent(RTLExpression.self, forKey: .condition)
        let loopVariable = try container.decode(String.self, forKey: .loopVariable)
        let start = try container.decode(Int64.self, forKey: .start)
        let limit = try container.decode(Int64.self, forKey: .limit)
        let step = try container.decode(Int64.self, forKey: .step)
        let startExpression = try container.decodeIfPresent(RTLExpression.self, forKey: .startExpression)
        let limitExpression = try container.decodeIfPresent(RTLExpression.self, forKey: .limitExpression)
        let stepExpression = try container.decodeIfPresent(RTLExpression.self, forKey: .stepExpression)
        let instances = try container.decode([RTLInstance].self, forKey: .instances)
        let assignments = try container.decode([RTLAssignment].self, forKey: .assignments)
        let source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .source)
        self.init(id: id, label: label, kind: kind, condition: condition, loopVariable: loopVariable, start: start, limit: limit, step: step, startExpression: startExpression, limitExpression: limitExpression, stepExpression: stepExpression, instances: instances, assignments: assignments, source: source)
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
