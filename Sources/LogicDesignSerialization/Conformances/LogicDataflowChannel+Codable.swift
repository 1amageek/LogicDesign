import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicDataflowChannel: Codable {
    private enum CodingKeys: String, CodingKey { case `id`, `name`, `type`, `kind`, `operations`, `flowControl`, `initialValues`, `strictness`, `fifoConfiguration` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UInt64.self, forKey: .`id`)
        let name = try container.decode(String.self, forKey: .`name`)
        let type = try container.decode(LogicDataflowType.self, forKey: .`type`)
        let kind = try container.decode(Kind.self, forKey: .`kind`)
        let operations = try container.decode(Operations.self, forKey: .`operations`)
        let flowControl = try container.decodeIfPresent(FlowControl.self, forKey: .`flowControl`)
        let initialValues = try container.decode([LogicDataflowValue].self, forKey: .`initialValues`)
        let strictness = try container.decodeIfPresent(LogicDataflowChannelStrictness.self, forKey: .`strictness`)
        let fifoConfiguration = try container.decodeIfPresent(LogicDataflowFIFOConfiguration.self, forKey: .`fifoConfiguration`)
        self.init(id: id, name: name, type: type, kind: kind, operations: operations, flowControl: flowControl, initialValues: initialValues, strictness: strictness, fifoConfiguration: fifoConfiguration)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .`id`)
        try container.encode(name, forKey: .`name`)
        try container.encode(type, forKey: .`type`)
        try container.encode(kind, forKey: .`kind`)
        try container.encode(operations, forKey: .`operations`)
        try container.encodeIfPresent(flowControl, forKey: .`flowControl`)
        try container.encode(initialValues, forKey: .`initialValues`)
        try container.encodeIfPresent(strictness, forKey: .`strictness`)
        try container.encodeIfPresent(fifoConfiguration, forKey: .`fifoConfiguration`)
    }
}
