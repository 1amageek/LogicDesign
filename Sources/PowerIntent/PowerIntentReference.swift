import Foundation
import CircuiteFoundation
import LogicIR

public struct PowerIntentReference: Sendable, Hashable, Codable {
    /// Immutable identity of the materialized power-intent artifact.
    public var artifact: ArtifactReference
    public var designDigest: String

    public init(
        artifact: ArtifactReference,
        designDigest: String
    ) {
        self.artifact = artifact
        self.designDigest = designDigest
    }
}
