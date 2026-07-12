import Foundation
import XcircuitePackage

public struct LogicDesignReference: Sendable, Hashable, Codable {
    public var artifact: XcircuiteFileReference
    public var topDesignName: String
    /// Canonical digest of the referenced design content; artifact.sha256 protects serialized bytes.
    public var designDigest: String

    public init(
        artifact: XcircuiteFileReference,
        topDesignName: String,
        designDigest: String
    ) {
        self.artifact = artifact
        self.topDesignName = topDesignName
        self.designDigest = designDigest
    }
}
