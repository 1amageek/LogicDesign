import Foundation
import CircuiteFoundation

public struct LogicDesignReference: Sendable, Hashable, Codable {
    /// Immutable identity of the materialized design artifact.
    public var artifact: ArtifactReference
    public var topDesignName: String
    /// Canonical digest of the referenced design content; the artifact digest protects serialized bytes.
    public var designDigest: String
    /// Optional lineage for a design produced by a transformation stage.
    public var provenance: LogicDesignProvenance?

    public init(
        artifact: ArtifactReference,
        topDesignName: String,
        designDigest: String,
        provenance: LogicDesignProvenance? = nil
    ) {
        self.artifact = artifact
        self.topDesignName = topDesignName
        self.designDigest = designDigest
        self.provenance = provenance
    }
}
