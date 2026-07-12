import Foundation
import XcircuitePackage
import LogicIR

public struct LogicElaborationRequest: XcircuiteEngineRequest {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [XcircuiteFileReference]

    public var topDesignName: String
    public var sources: [SystemVerilogSourceUnit]

    public init(
        runID: String,
        inputs: [XcircuiteFileReference],
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
