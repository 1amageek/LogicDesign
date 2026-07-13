import Foundation

public struct LogicDesignOracleObservation: Sendable, Hashable, Codable {
    public var caseID: String
    public var sourceSHA256: String
    public var topDesignName: String
    public var status: String
    public var snapshotDigest: String?
    public var diagnosticCodes: [String]
    public var implementationID: String
    public var implementationVersion: String

    public init(
        caseID: String,
        sourceSHA256: String,
        topDesignName: String,
        status: String,
        snapshotDigest: String?,
        diagnosticCodes: [String],
        implementationID: String,
        implementationVersion: String
    ) {
        self.caseID = caseID
        self.sourceSHA256 = sourceSHA256
        self.topDesignName = topDesignName
        self.status = status
        self.snapshotDigest = snapshotDigest
        self.diagnosticCodes = diagnosticCodes
        self.implementationID = implementationID
        self.implementationVersion = implementationVersion
    }
}
