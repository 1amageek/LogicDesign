import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension GateDesign: Codable {
    private enum CodingKeys: String, CodingKey { case `schemaVersion`, `topModuleName`, `modules` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .`schemaVersion`)
        let topModuleName = try container.decode(String.self, forKey: .`topModuleName`)
        let modules = try container.decode([GateModule].self, forKey: .`modules`)
        self.init(topModuleName: topModuleName, modules: modules, schemaVersion: schemaVersion)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .`schemaVersion`)
        try container.encode(topModuleName, forKey: .`topModuleName`)
        try container.encode(modules, forKey: .`modules`)
    }
}
