import Foundation
import LogicIR

public struct PowerIntentDesign: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var format: PowerIntentFormat
    public var domains: [PowerDomain]
    public var supplySets: [PowerSupplySet]
    public var isolationPolicies: [PowerIntentIsolation]
    public var levelShifters: [PowerIntentLevelShifter]
    public var retentionPolicies: [PowerIntentRetention]
    public var directives: [String]
    public var sourceFiles: [LogicSourceFile]

    public init(
        format: PowerIntentFormat,
        domains: [PowerDomain] = [],
        supplySets: [PowerSupplySet] = [],
        isolationPolicies: [PowerIntentIsolation] = [],
        levelShifters: [PowerIntentLevelShifter] = [],
        retentionPolicies: [PowerIntentRetention] = [],
        directives: [String] = [],
        sourceFiles: [LogicSourceFile] = [],
        schemaVersion: Int = PowerIntentDesign.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.format = format
        self.domains = domains
        self.supplySets = supplySets
        self.isolationPolicies = isolationPolicies
        self.levelShifters = levelShifters
        self.retentionPolicies = retentionPolicies
        self.directives = directives
        self.sourceFiles = sourceFiles
    }
}
