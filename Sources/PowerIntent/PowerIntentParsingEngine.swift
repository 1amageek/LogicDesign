import Foundation
import LogicIR
import CircuiteFoundation

public struct PowerIntentParsingEngine: PowerIntentParsing {
    private let parser: PowerIntentParser
    private let validator: PowerIntentValidator
    private let sourceProvider: PowerIntentSourceProviding
    private let clock: @Sendable () -> Date

    public init(
        parser: PowerIntentParser = PowerIntentParser(),
        validator: PowerIntentValidator = PowerIntentValidator(),
        sourceProvider: PowerIntentSourceProviding = FileSystemPowerIntentSourceProvider(),
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.parser = parser
        self.validator = validator
        self.sourceProvider = sourceProvider
        self.clock = clock
    }

    public func execute(
        _ request: PowerIntentParsingRequest
    ) async throws -> PowerIntentParsingResult {
        let startedAt = clock()
        do {
            try Task.checkCancellation()
            let contract = LogicRequestContractValidator().validate(
                schemaVersion: request.schemaVersion,
                expectedSchemaVersion: PowerIntentParsingRequest.currentSchemaVersion,
                runID: request.runID,
                inputs: request.inputs,
                topDesignName: request.design.topDesignName,
                inlineSourceCount: request.sources.count
            )
            guard contract.isValid else {
                return try makeResult(
                    request: request,
                    status: .failed,
                    diagnostics: contract.diagnostics,
                    payload: PowerIntentParsingPayload(reference: nil, domainCount: 0),
                    startedAt: startedAt
                )
            }
            guard !request.design.designDigest.isEmpty else {
                return try makeResult(
                    request: request,
                    status: .blocked,
                    diagnostics: [LogicDiagnostic(
                        severity: .error,
                        code: "POWER_DESIGN_DIGEST_MISSING",
                        message: "Power intent parsing requires the canonical design digest.",
                        suggestedActions: ["provide_canonical_design_reference"]
                    )],
                    payload: PowerIntentParsingPayload(reference: nil, domainCount: 0),
                    startedAt: startedAt
                )
            }
            let sources = try resolveSources(request)
            let parsed = parser.parse(sources)
            guard let intent = parsed.design else {
                return try makeResult(
                    request: request,
                    status: .failed,
                    diagnostics: parsed.diagnostics,
                    payload: PowerIntentParsingPayload(reference: nil, domainCount: 0),
                    startedAt: startedAt
                )
            }
            let validation = validator.validate(intent)
            let status: LogicExecutionStatus
            if parsed.unsupportedSemantics {
                status = .blocked
            } else if parsed.diagnostics.contains(where: { $0.severity == .error }) || !validation.isValid {
                status = .failed
            } else {
                status = .completed
            }
            return try makeResult(
                request: request,
                status: status,
                diagnostics: parsed.diagnostics + validation.diagnostics,
                payload: PowerIntentParsingPayload(
                    reference: nil,
                    domainCount: intent.domains.count,
                    intent: intent,
                    validation: validation
                ),
                startedAt: startedAt
            )
        } catch is CancellationError {
            return try makeResult(
                request: request,
                status: .cancelled,
                diagnostics: [LogicDiagnostic(
                    severity: .warning,
                    code: "POWER_EXECUTION_CANCELLED",
                    message: "Power intent parsing was cancelled.",
                    suggestedActions: ["resume_run"]
                )],
                payload: PowerIntentParsingPayload(reference: nil, domainCount: 0),
                startedAt: startedAt
            )
        } catch {
            return try makeResult(
                request: request,
                status: .failed,
                diagnostics: [LogicDiagnostic(
                    severity: .error,
                    code: "POWER_SOURCE_LOAD_FAILED",
                    message: error.localizedDescription,
                    suggestedActions: ["check_input_artifact", "verify_project_relative_path"]
                )],
                payload: PowerIntentParsingPayload(reference: nil, domainCount: 0),
                startedAt: startedAt
            )
        }
    }

    private func resolveSources(_ request: PowerIntentParsingRequest) throws -> [PowerIntentSourceUnit] {
        if !request.sources.isEmpty { return request.sources }
        return try request.inputs.map { try sourceProvider.load($0, format: request.format) }
    }

    private func makeResult(
        request: PowerIntentParsingRequest,
        status: LogicExecutionStatus,
        diagnostics: [LogicDiagnostic],
        payload: PowerIntentParsingPayload,
        startedAt: Date
    ) throws -> PowerIntentParsingResult {
        PowerIntentParsingResult(
            schemaVersion: PowerIntentParsingRequest.currentSchemaVersion,
            runID: request.runID,
            status: status,
            logicDiagnostics: diagnostics,
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(
                    kind: .engine,
                    identifier: "LogicDesign.PowerIntent",
                    version: "1",
                    build: "native-upf-cpf-subset"
                ),
                invocation: ExecutionInvocation.inProcess(
                    entryPoint: "PowerIntentParsingEngine.execute"
                ),
                startedAt: startedAt,
                completedAt: clock()
            ),
            payload: payload
        )
    }
}
