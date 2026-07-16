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
    public var structuredDirectives: [PowerIntentDirective]
    public var sourceFiles: [LogicSourceFile]

    public init(
        format: PowerIntentFormat,
        domains: [PowerDomain] = [],
        supplySets: [PowerSupplySet] = [],
        isolationPolicies: [PowerIntentIsolation] = [],
        levelShifters: [PowerIntentLevelShifter] = [],
        retentionPolicies: [PowerIntentRetention] = [],
        directives: [String] = [],
        structuredDirectives: [PowerIntentDirective] = [],
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
        self.structuredDirectives = structuredDirectives
        self.sourceFiles = sourceFiles
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case format
        case domains
        case supplySets
        case isolationPolicies
        case levelShifters
        case retentionPolicies
        case directives
        case structuredDirectives
        case sourceFiles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported power intent schema version \(schemaVersion)."
            )
        }
        format = try container.decode(PowerIntentFormat.self, forKey: .format)
        domains = try container.decode([PowerDomain].self, forKey: .domains)
        supplySets = try container.decode([PowerSupplySet].self, forKey: .supplySets)
        isolationPolicies = try container.decode([PowerIntentIsolation].self, forKey: .isolationPolicies)
        levelShifters = try container.decode([PowerIntentLevelShifter].self, forKey: .levelShifters)
        retentionPolicies = try container.decode([PowerIntentRetention].self, forKey: .retentionPolicies)
        directives = try container.decode([String].self, forKey: .directives)
        structuredDirectives = try container.decode([PowerIntentDirective].self, forKey: .structuredDirectives)
        sourceFiles = try container.decode([LogicSourceFile].self, forKey: .sourceFiles)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(format, forKey: .format)
        try container.encode(domains, forKey: .domains)
        try container.encode(supplySets, forKey: .supplySets)
        try container.encode(isolationPolicies, forKey: .isolationPolicies)
        try container.encode(levelShifters, forKey: .levelShifters)
        try container.encode(retentionPolicies, forKey: .retentionPolicies)
        try container.encode(directives, forKey: .directives)
        try container.encode(structuredDirectives, forKey: .structuredDirectives)
        try container.encode(sourceFiles, forKey: .sourceFiles)
    }
}
