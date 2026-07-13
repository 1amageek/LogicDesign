import Foundation

public struct LogicDesignOracleCase: Sendable, Hashable, Codable {
    public var id: String
    public var sourcePath: String
    public var sourceSHA256: String
    public var topDesignName: String
    public var expectedStatus: String
    public var expectedSnapshotDigest: String?
    public var expectedDiagnosticCodes: [String]

    public init(
        id: String,
        sourcePath: String,
        sourceSHA256: String,
        topDesignName: String,
        expectedStatus: String,
        expectedSnapshotDigest: String? = nil,
        expectedDiagnosticCodes: [String] = []
    ) {
        self.id = id
        self.sourcePath = sourcePath
        self.sourceSHA256 = sourceSHA256
        self.topDesignName = topDesignName
        self.expectedStatus = expectedStatus
        self.expectedSnapshotDigest = expectedSnapshotDigest
        self.expectedDiagnosticCodes = expectedDiagnosticCodes
    }
}
