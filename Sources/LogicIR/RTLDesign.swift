import Foundation

public struct RTLDesign: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var topModuleName: String
    public var modules: [RTLModule]
    public var sourceFiles: [LogicSourceFile]

    public init(
        topModuleName: String,
        modules: [RTLModule] = [],
        sourceFiles: [LogicSourceFile] = [],
        schemaVersion: Int = RTLDesign.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.topModuleName = topModuleName
        self.modules = modules
        self.sourceFiles = sourceFiles
    }
}
