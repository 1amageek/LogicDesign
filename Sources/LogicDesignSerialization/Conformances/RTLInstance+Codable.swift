import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension RTLInstance: Codable {
    private enum CodingKeys: String, CodingKey { case `id`, `moduleName`, `instanceName`, `parameterOverrides`, `connections`, `source` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .`id`)
        let moduleName = try container.decode(String.self, forKey: .`moduleName`)
        let instanceName = try container.decode(String.self, forKey: .`instanceName`)
        let parameterOverrides = try container.decode([String: Int64].self, forKey: .`parameterOverrides`)
        let connections = try container.decode([RTLPortConnection].self, forKey: .`connections`)
        let source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .`source`)
        self.init(id: id, moduleName: moduleName, instanceName: instanceName, parameterOverrides: parameterOverrides, connections: connections, source: source)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .`id`)
        try container.encode(moduleName, forKey: .`moduleName`)
        try container.encode(instanceName, forKey: .`instanceName`)
        try container.encode(parameterOverrides, forKey: .`parameterOverrides`)
        try container.encode(connections, forKey: .`connections`)
        try container.encodeIfPresent(source, forKey: .`source`)
    }
}
