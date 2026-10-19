import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicDataflowProcess: Codable {
    private enum CodingKeys: String, CodingKey { case `name`, `stateElements`, `nodes`, `nextStateValues` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .`name`)
        let stateElements = try container.decode([LogicDataflowStateElement].self, forKey: .`stateElements`)
        let nodes = try container.decode([LogicDataflowNode].self, forKey: .`nodes`)
        let nextStateValues = try container.decode([String].self, forKey: .`nextStateValues`)
        self.init(name: name, stateElements: stateElements, nodes: nodes, nextStateValues: nextStateValues)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .`name`)
        try container.encode(stateElements, forKey: .`stateElements`)
        try container.encode(nodes, forKey: .`nodes`)
        try container.encode(nextStateValues, forKey: .`nextStateValues`)
    }
}
