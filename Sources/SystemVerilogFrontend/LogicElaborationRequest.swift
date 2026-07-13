import Foundation
import CircuiteFoundation
import LogicIR

public struct LogicElaborationRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [ArtifactLocator]

    public var topDesignName: String
    public var sources: [SystemVerilogSourceUnit]

    public init(
        runID: String,
        inputs: [ArtifactLocator],
        topDesignName: String,
        sources: [SystemVerilogSourceUnit] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.inputs = inputs
        self.topDesignName = topDesignName
        self.sources = sources
    }
}
