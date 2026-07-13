import Foundation

public struct LogicDesignOracleManifest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var oracleID: String
    public var oracleVersion: String
    public var corpusID: String
    public var cases: [LogicDesignOracleCase]

    public init(
        oracleID: String,
        oracleVersion: String,
        corpusID: String,
        cases: [LogicDesignOracleCase],
        schemaVersion: Int = LogicDesignOracleManifest.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.oracleID = oracleID
        self.oracleVersion = oracleVersion
        self.corpusID = corpusID
        self.cases = cases
    }

    public func caseWithID(_ id: String) -> LogicDesignOracleCase? {
        cases.first { $0.id == id }
    }
}
