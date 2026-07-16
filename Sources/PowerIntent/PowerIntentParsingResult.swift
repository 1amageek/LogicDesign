import Foundation
import CircuiteFoundation
import LogicIR

/// Result of a power-intent parsing execution.
public struct PowerIntentParsingResult: Sendable, Hashable, Codable {
    public let schemaVersion: Int
    public let runID: String
    public let status: LogicExecutionStatus
    public let diagnostics: [LogicDiagnostic]
    public let provenance: ExecutionProvenance
    public let payload: PowerIntentParsingPayload

    public init(
        schemaVersion: Int,
        runID: String,
        status: LogicExecutionStatus,
        diagnostics: [LogicDiagnostic] = [],
        provenance: ExecutionProvenance,
        payload: PowerIntentParsingPayload
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.diagnostics = diagnostics
        self.provenance = provenance
        self.payload = payload
    }
}
