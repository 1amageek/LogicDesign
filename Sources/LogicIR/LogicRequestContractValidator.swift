import Foundation
import XcircuitePackage

public struct LogicRequestContractValidator: LogicRequestContractValidating {
    public init() {}

    public func validate(
        schemaVersion: Int,
        expectedSchemaVersion: Int,
        runID: String,
        inputs: [XcircuiteFileReference],
        topDesignName: String,
        inlineSourceCount: Int
    ) -> LogicValidationResult {
        var diagnostics: [LogicDiagnostic] = []
        if schemaVersion != expectedSchemaVersion {
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "LOGIC_REQUEST_SCHEMA_UNSUPPORTED",
                message: "The request schema version is not supported by this engine.",
                entity: String(schemaVersion),
                suggestedActions: ["upgrade_request_schema", "select_compatible_engine"]
            ))
        }
        if runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "LOGIC_REQUEST_RUN_ID_MISSING",
                message: "Every logic-design execution requires a non-empty run ID.",
                suggestedActions: ["provide_run_id"]
            ))
        }
        if topDesignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "LOGIC_REQUEST_TOP_MISSING",
                message: "Every logic-design execution requires a top design name.",
                suggestedActions: ["select_top_module"]
            ))
        }
        if inputs.isEmpty && inlineSourceCount == 0 {
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "LOGIC_REQUEST_INPUT_MISSING",
                message: "Execution requires artifact inputs or explicitly injected inline sources.",
                suggestedActions: ["provide_input_artifact", "provide_inline_source_for_test"]
            ))
        }
        for input in inputs {
            if input.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "LOGIC_REQUEST_INPUT_PATH_MISSING",
                    message: "Input artifact references require a non-empty project-relative path.",
                    suggestedActions: ["provide_input_artifact_path"]
                ))
            }
            if let byteCount = input.byteCount, byteCount < 0 {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "LOGIC_REQUEST_INPUT_BYTE_COUNT_INVALID",
                    message: "Input artifact byte counts must be non-negative.",
                    entity: input.path,
                    suggestedActions: ["recompute_artifact_reference"]
                ))
            }
            if let sha256 = input.sha256, !isSHA256(sha256) {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "LOGIC_REQUEST_INPUT_DIGEST_INVALID",
                    message: "Input artifact SHA-256 must be a 64-character hexadecimal value.",
                    entity: input.path,
                    suggestedActions: ["recompute_artifact_reference"]
                ))
            }
            if inlineSourceCount == 0 && (input.sha256 == nil || input.byteCount == nil) {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "LOGIC_REQUEST_INPUT_INTEGRITY_MISSING",
                    message: "Filesystem-backed inputs must include SHA-256 and byte-count integrity metadata.",
                    entity: input.path,
                    suggestedActions: ["recompute_artifact_reference", "use_verified_stage_artifact"]
                ))
            }
        }
        return LogicValidationResult(
            isValid: !diagnostics.contains { $0.severity == .error },
            diagnostics: diagnostics
        )
    }

    private func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 70)
                || (byte >= 97 && byte <= 102)
        }
    }
}
