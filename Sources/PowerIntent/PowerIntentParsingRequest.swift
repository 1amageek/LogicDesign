import Foundation
import XcircuitePackage
import LogicIR

public struct PowerIntentParsingRequest: XcircuiteEngineRequest {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [XcircuiteFileReference]
    public var design: LogicDesignReference
    public var format: PowerIntentFormat
    public var sources: [PowerIntentSourceUnit]

    public init(
        runID: String,
        inputs: [XcircuiteFileReference],
        design: LogicDesignReference,
        format: PowerIntentFormat = .upf,
        sources: [PowerIntentSourceUnit] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.inputs = inputs
        self.design = design
        self.format = format
        self.sources = sources
    }
}
