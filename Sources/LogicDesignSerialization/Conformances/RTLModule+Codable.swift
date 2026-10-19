import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension RTLModule: Codable {
    private enum CodingKeys: String, CodingKey { case `id`, `name`, `parameters`, `ports`, `signals`, `memories`, `assignments`, `processes`, `instances`, `generateBlocks`, `source` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .`id`)
        let name = try container.decode(String.self, forKey: .`name`)
        let parameters = try container.decode([RTLParameter].self, forKey: .`parameters`)
        let ports = try container.decode([RTLPort].self, forKey: .`ports`)
        let signals = try container.decode([RTLSignal].self, forKey: .`signals`)
        let memories = try container.decode([RTLMemory].self, forKey: .`memories`)
        let assignments = try container.decode([RTLAssignment].self, forKey: .`assignments`)
        let processes = try container.decode([RTLProcess].self, forKey: .`processes`)
        let instances = try container.decode([RTLInstance].self, forKey: .`instances`)
        let generateBlocks = try container.decode([RTLGenerateBlock].self, forKey: .`generateBlocks`)
        let source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .`source`)
        self.init(id: id, name: name, parameters: parameters, ports: ports, signals: signals, memories: memories, assignments: assignments, processes: processes, instances: instances, generateBlocks: generateBlocks, source: source)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .`id`)
        try container.encode(name, forKey: .`name`)
        try container.encode(parameters, forKey: .`parameters`)
        try container.encode(ports, forKey: .`ports`)
        try container.encode(signals, forKey: .`signals`)
        try container.encode(memories, forKey: .`memories`)
        try container.encode(assignments, forKey: .`assignments`)
        try container.encode(processes, forKey: .`processes`)
        try container.encode(instances, forKey: .`instances`)
        try container.encode(generateBlocks, forKey: .`generateBlocks`)
        try container.encodeIfPresent(source, forKey: .`source`)
    }
}
