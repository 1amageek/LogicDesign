import Foundation

public struct LogicDesignOracleCorrelation: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var oracleID: String
    public var oracleVersion: String
    public var corpusID: String
    public var manifestDigest: String
    public var caseID: String
    public var caseDigest: String
    public var matched: Bool
    public var observation: LogicDesignOracleObservation
    public var mismatches: [LogicDesignOracleMismatch]

    public init(
        oracleID: String,
        oracleVersion: String,
        corpusID: String,
        manifestDigest: String,
        caseID: String,
        caseDigest: String,
        matched: Bool,
        observation: LogicDesignOracleObservation,
        mismatches: [LogicDesignOracleMismatch],
        schemaVersion: Int = LogicDesignOracleCorrelation.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.oracleID = oracleID
        self.oracleVersion = oracleVersion
        self.corpusID = corpusID
        self.manifestDigest = manifestDigest
        self.caseID = caseID
        self.caseDigest = caseDigest
        self.matched = matched
        self.observation = observation
        self.mismatches = mismatches
    }

    public static let currentSchemaVersion = 2
}
