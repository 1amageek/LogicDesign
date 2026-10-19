import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension RTLDesign: Codable {
    private enum CodingKeys: String, CodingKey { case `schemaVersion`, `topModuleName`, `modules`, `sourceFiles` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .`schemaVersion`)
        let topModuleName = try container.decode(String.self, forKey: .`topModuleName`)
        let modules = try container.decode([RTLModule].self, forKey: .`modules`)
        let sourceFiles = try container.decode([LogicSourceFile].self, forKey: .`sourceFiles`)
        self.init(topModuleName: topModuleName, modules: modules, sourceFiles: sourceFiles, schemaVersion: schemaVersion)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .`schemaVersion`)
        try container.encode(topModuleName, forKey: .`topModuleName`)
        try container.encode(modules, forKey: .`modules`)
        try container.encode(sourceFiles, forKey: .`sourceFiles`)
    }
}
