import Foundation

public struct GateDesign: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var topModuleName: String
    public var modules: [GateModule]

    public init(
        topModuleName: String,
        modules: [GateModule] = [],
        schemaVersion: Int = GateDesign.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.topModuleName = topModuleName
        self.modules = modules
    }
}
