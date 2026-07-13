import Foundation

/// Domain execution metadata retained by logic-design results.
public struct LogicExecutionMetadata: Sendable, Hashable, Codable {
    public let engineID: String
    public let implementationID: String
    public let implementationVersion: String
    public let startedAt: Date
    public let completedAt: Date

    public init(
        engineID: String,
        implementationID: String,
        implementationVersion: String,
        startedAt: Date,
        completedAt: Date
    ) {
        self.engineID = engineID
        self.implementationID = implementationID
        self.implementationVersion = implementationVersion
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}
