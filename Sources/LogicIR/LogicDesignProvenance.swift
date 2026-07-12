import Foundation

/// Records the canonical design lineage carried by a transformed design handoff.
public struct LogicDesignProvenance: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Digest of the original canonical design identity carried through the flow.
    public var sourceDesignDigest: String
    /// Digest of the immediate input design consumed by the producer, when transformed.
    public var inputDesignDigest: String?
    /// Stable operation identifier for the transformation that produced the handoff.
    public var transformationID: String?
    public var producerID: String
    public var producerVersion: String
    public var runID: String?

    public init(
        sourceDesignDigest: String,
        inputDesignDigest: String? = nil,
        transformationID: String? = nil,
        producerID: String,
        producerVersion: String,
        runID: String? = nil,
        schemaVersion: Int = LogicDesignProvenance.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.sourceDesignDigest = sourceDesignDigest
        self.inputDesignDigest = inputDesignDigest
        self.transformationID = transformationID
        self.producerID = producerID
        self.producerVersion = producerVersion
        self.runID = runID
    }

    public var isValid: Bool {
        guard schemaVersion == Self.currentSchemaVersion,
              !sourceDesignDigest.isEmpty,
              !producerID.isEmpty,
              !producerVersion.isEmpty else {
            return false
        }
        if let inputDesignDigest, inputDesignDigest.isEmpty {
            return false
        }
        if let transformationID, transformationID.isEmpty {
            return false
        }
        if let runID, runID.isEmpty {
            return false
        }
        return true
    }

    public var canonicalMaterial: String {
        [
            String(schemaVersion),
            sourceDesignDigest,
            inputDesignDigest ?? "",
            transformationID ?? "",
            producerID,
            producerVersion,
            runID ?? "",
        ].joined(separator: "|")
    }
}
