import Foundation
import LogicIR
import CircuiteFoundation

public struct LogicElaboratingEngine: LogicElaborating {
    private let parser: SystemVerilogParsing
    private let validator: LogicDesignValidating
    private let hierarchyElaborator: any RTLHierarchyElaborating
    private let sourceProvider: SystemVerilogSourceProviding
    private let sourceResolver: SystemVerilogSourceResolving
    private let clock: @Sendable () -> Date

    public init(
        parser: SystemVerilogParsing = SystemVerilogParser(),
        validator: LogicDesignValidating = LogicDesignValidator(),
        hierarchyElaborator: any RTLHierarchyElaborating = RTLHierarchyElaborator(),
        sourceProvider: SystemVerilogSourceProviding = FileSystemSystemVerilogSourceProvider(),
        sourceResolver: SystemVerilogSourceResolving? = nil,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.parser = parser
        self.validator = validator
        self.hierarchyElaborator = hierarchyElaborator
        self.sourceProvider = sourceProvider
        self.sourceResolver = sourceResolver ?? SystemVerilogSourceResolver(sourceProvider: sourceProvider)
        self.clock = clock
    }

    public func execute(
        _ request: LogicElaborationRequest
    ) async throws -> LogicElaborationResult {
        let startedAt = clock()
        do {
            try Task.checkCancellation()
            let contract = LogicRequestContractValidator().validate(
                schemaVersion: request.schemaVersion,
                expectedSchemaVersion: LogicElaborationRequest.currentSchemaVersion,
                runID: request.runID,
                inputs: request.inputs,
                topDesignName: request.topDesignName,
                inlineSourceCount: request.sources.count
            )
            guard contract.isValid else {
                return envelope(
                    request: request,
                    status: .failed,
                    diagnostics: contract.diagnostics,
                    payload: LogicElaborationPayload(design: nil, sourceUnitCount: 0),
                    startedAt: startedAt
                )
            }
            let sources = try resolveSources(request)
            let parseResult = parser.parseResolvedIncludes(sources, topDesignName: request.topDesignName)
            if parseResult.unsupportedSemantics {
                return envelope(
                    request: request,
                    status: .blocked,
                    diagnostics: parseResult.diagnostics,
                    payload: LogicElaborationPayload(
                        design: nil,
                        sourceUnitCount: sources.count,
                        snapshot: nil,
                        validation: nil
                    ),
                    startedAt: startedAt
                )
            }
            guard let design = parseResult.design else {
                return envelope(
                    request: request,
                    status: .failed,
                    diagnostics: parseResult.diagnostics + [LogicDiagnostic(
                        severity: .error,
                        code: "SV_DESIGN_EMPTY",
                        message: "No module was parsed from the input sources.",
                        suggestedActions: ["provide_systemverilog_module"]
                    )],
                    payload: LogicElaborationPayload(design: nil, sourceUnitCount: sources.count),
                    startedAt: startedAt
                )
            }

            let hierarchyResult = hierarchyElaborator.elaborate(design)
            guard let elaboratedDesign = hierarchyResult.design else {
                return envelope(
                    request: request,
                    status: .blocked,
                    diagnostics: parseResult.diagnostics + hierarchyResult.diagnostics,
                    payload: LogicElaborationPayload(
                        design: nil,
                        sourceUnitCount: sources.count,
                        snapshot: nil,
                        validation: nil
                    ),
                    startedAt: startedAt
                )
            }
            let validation = validator.validate(elaboratedDesign)
            if parseResult.diagnostics.contains(where: { $0.severity == .error }) || !validation.isValid {
                return envelope(
                    request: request,
                    status: .failed,
                    diagnostics: parseResult.diagnostics + validation.diagnostics,
                    payload: LogicElaborationPayload(
                        design: nil,
                        sourceUnitCount: sources.count,
                        snapshot: LogicDesignSnapshot(rtl: elaboratedDesign),
                        validation: validation
                    ),
                    startedAt: startedAt
                )
            }

            let snapshot = try LogicDesignSnapshotCodec.finalized(
                LogicDesignSnapshot(rtl: elaboratedDesign)
            )
            return envelope(
                request: request,
                status: .completed,
                diagnostics: parseResult.diagnostics + validation.diagnostics,
                payload: LogicElaborationPayload(
                    design: nil,
                    sourceUnitCount: sources.count,
                    snapshot: snapshot,
                    validation: validation
                ),
                startedAt: startedAt
            )
        } catch is CancellationError {
            return envelope(
                request: request,
                status: .cancelled,
                diagnostics: [LogicDiagnostic(
                    severity: .warning,
                    code: "SV_EXECUTION_CANCELLED",
                    message: "SystemVerilog elaboration was cancelled.",
                    suggestedActions: ["resume_run"]
                )],
                payload: LogicElaborationPayload(design: nil, sourceUnitCount: 0),
                startedAt: startedAt
            )
        } catch let error as SystemVerilogSourceResolutionError {
            return envelope(
                request: request,
                status: .failed,
                diagnostics: [LogicDiagnostic(
                    severity: .error,
                    code: error.diagnosticCode,
                    message: error.localizedDescription,
                    location: error.location,
                    suggestedActions: ["add_missing_include", "correct_include_path", "remove_include_cycle"]
                )],
                payload: LogicElaborationPayload(
                    design: nil,
                    sourceUnitCount: request.sources.count
                ),
                startedAt: startedAt
            )
        } catch {
            return envelope(
                request: request,
                status: .failed,
                diagnostics: [LogicDiagnostic(
                    severity: .error,
                    code: "SV_SOURCE_LOAD_FAILED",
                    message: error.localizedDescription,
                    suggestedActions: ["check_input_artifact", "verify_project_relative_path"]
                )],
                payload: LogicElaborationPayload(design: nil, sourceUnitCount: 0),
                startedAt: startedAt
            )
        }
    }

    private func resolveSources(_ request: LogicElaborationRequest) throws -> [SystemVerilogSourceUnit] {
        let initialSources: [SystemVerilogSourceUnit]
        if !request.sources.isEmpty {
            initialSources = request.sources
        } else {
            initialSources = try request.inputs.map(sourceProvider.load)
        }
        return try sourceResolver.resolve(initialSources)
    }

    private func envelope(
        request: LogicElaborationRequest,
        status: LogicExecutionStatus,
        diagnostics: [LogicDiagnostic],
        payload: LogicElaborationPayload,
        startedAt: Date
    ) -> LogicElaborationResult {
        LogicElaborationResult(
            schemaVersion: LogicElaborationRequest.currentSchemaVersion,
            runID: request.runID,
            status: status,
            diagnostics: diagnostics,
            metadata: LogicExecutionMetadata(
                engineID: "LogicDesign.SystemVerilogFrontend",
                implementationID: "native-systemverilog-subset",
                implementationVersion: "1",
                startedAt: startedAt,
                completedAt: clock()
            ),
            payload: payload
        )
    }
}
