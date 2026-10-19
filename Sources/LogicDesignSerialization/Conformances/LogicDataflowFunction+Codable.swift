import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicDataflowFunction: Codable {
    private enum CodingKeys: String, CodingKey { case `name`, `parameters`, `returnType`, `nodes`, `returnValue` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .`name`)
        let parameters = try container.decode([LogicDataflowParameter].self, forKey: .`parameters`)
        let returnType = try container.decode(LogicDataflowType.self, forKey: .`returnType`)
        let nodes = try container.decode([LogicDataflowNode].self, forKey: .`nodes`)
        let returnValue = try container.decode(String.self, forKey: .`returnValue`)
        self.init(name: name, parameters: parameters, returnType: returnType, nodes: nodes, returnValue: returnValue)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .`name`)
        try container.encode(parameters, forKey: .`parameters`)
        try container.encode(returnType, forKey: .`returnType`)
        try container.encode(nodes, forKey: .`nodes`)
        try container.encode(returnValue, forKey: .`returnValue`)
    }
}
