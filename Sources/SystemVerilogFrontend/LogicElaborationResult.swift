import Foundation
import LogicIR

/// Result of a SystemVerilog elaboration execution.
public struct LogicElaborationResult: Sendable, Hashable, Codable {
    public let schemaVersion: Int
    public let runID: String
    public let status: LogicExecutionStatus
    public let diagnostics: [LogicDiagnostic]
    public let metadata: LogicExecutionMetadata
    public let payload: LogicElaborationPayload

    public init(
        schemaVersion: Int,
        runID: String,
        status: LogicExecutionStatus,
        diagnostics: [LogicDiagnostic] = [],
        metadata: LogicExecutionMetadata,
        payload: LogicElaborationPayload
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.diagnostics = diagnostics
        self.metadata = metadata
        self.payload = payload
    }
}
