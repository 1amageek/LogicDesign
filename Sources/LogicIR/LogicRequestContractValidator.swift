import Foundation
import CircuiteFoundation

public struct LogicRequestContractValidator: LogicRequestContractValidating {
    public init() {}

    public func validate(
        schemaVersion: Int,
        expectedSchemaVersion: Int,
        runID: String,
        inputs: [ArtifactLocator],
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
            if input.location.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "LOGIC_REQUEST_INPUT_PATH_MISSING",
                    message: "Input artifact references require a non-empty project-relative path.",
                    suggestedActions: ["provide_input_artifact_path"]
                ))
            }
        }
        return LogicValidationResult(
            isValid: !diagnostics.contains { $0.severity == .error },
            diagnostics: diagnostics
        )
    }

}
