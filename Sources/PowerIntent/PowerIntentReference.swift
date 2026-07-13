import Foundation
import CircuiteFoundation
import LogicIR

public struct PowerIntentReference: Sendable, Hashable, Codable {
    public var artifact: ArtifactLocator
    public var designDigest: String

    public init(
        artifact: ArtifactLocator,
        designDigest: String
    ) {
        self.artifact = artifact
        self.designDigest = designDigest
    }
}
