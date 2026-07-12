import Foundation
import XcircuitePackage
import LogicIR

public struct PowerIntentReference: Sendable, Hashable, Codable {
    public var artifact: XcircuiteFileReference
    public var designDigest: String

    public init(
        artifact: XcircuiteFileReference,
        designDigest: String
    ) {
        self.artifact = artifact
        self.designDigest = designDigest
    }
}
