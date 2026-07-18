import Foundation

public struct LogicDesignEvidenceBoundary: Sendable, Hashable, Codable {
    public let producedEvidence: [String]
    public let externalDecisions: [String]

    public init(
        producedEvidence: [String],
        externalDecisions: [String]
    ) {
        self.producedEvidence = producedEvidence
        self.externalDecisions = externalDecisions
    }
}
