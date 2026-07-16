import Foundation
import CircuiteFoundation
import LogicIR

/// Result of a power-intent parsing execution.
public struct PowerIntentParsingResult: Sendable, Hashable, Codable,
    ArtifactProducing, DiagnosticReporting, EvidenceProviding
{
    public let schemaVersion: Int
    public let runID: String
    public let status: LogicExecutionStatus
    public let logicDiagnostics: [LogicDiagnostic]
    public let provenance: ExecutionProvenance
    public let payload: PowerIntentParsingPayload

    public var artifacts: [ArtifactReference] {
        payload.reference.map { [$0.artifact] } ?? []
    }

    public var diagnostics: [DesignDiagnostic] {
        logicDiagnostics.map(\.engineDiagnostic)
    }

    public var evidence: EvidenceManifest {
        EvidenceManifest(provenance: provenance, artifacts: artifacts)
    }

    public init(
        schemaVersion: Int,
        runID: String,
        status: LogicExecutionStatus,
        logicDiagnostics: [LogicDiagnostic] = [],
        provenance: ExecutionProvenance,
        payload: PowerIntentParsingPayload
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.logicDiagnostics = logicDiagnostics
        self.provenance = provenance
        self.payload = payload
    }
}
