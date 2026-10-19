import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicDataflowDesign: Codable {
    private enum CodingKeys: String, CodingKey { case `packageName`, `topEntityName`, `functions`, `processes`, `channels` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let packageName = try container.decode(String.self, forKey: .`packageName`)
        let topEntityName = try container.decodeIfPresent(String.self, forKey: .`topEntityName`)
        let functions = try container.decode([LogicDataflowFunction].self, forKey: .`functions`)
        let processes = try container.decode([LogicDataflowProcess].self, forKey: .`processes`)
        let channels = try container.decode([LogicDataflowChannel].self, forKey: .`channels`)
        self.init(packageName: packageName, topEntityName: topEntityName, functions: functions, processes: processes, channels: channels)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(packageName, forKey: .`packageName`)
        try container.encodeIfPresent(topEntityName, forKey: .`topEntityName`)
        try container.encode(functions, forKey: .`functions`)
        try container.encode(processes, forKey: .`processes`)
        try container.encode(channels, forKey: .`channels`)
    }
}
