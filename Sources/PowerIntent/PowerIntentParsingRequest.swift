import Foundation
import CircuiteFoundation
import LogicIR

public struct PowerIntentParsingRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [ArtifactReference]
    public var design: LogicDesignReference
    public var format: PowerIntentFormat
    public var sources: [PowerIntentSourceUnit]

    public init(
        runID: String,
        inputs: [ArtifactReference],
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
