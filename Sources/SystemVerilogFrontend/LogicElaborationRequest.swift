import Foundation
import CircuiteFoundation
import LogicIR

public struct LogicElaborationRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [LogicArtifactInput]

    public var topDesignName: String
    public var sources: [SystemVerilogSourceUnit]

    public init(
        runID: String,
        inputs: [LogicArtifactInput],
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
