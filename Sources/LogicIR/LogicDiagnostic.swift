import Foundation
import CircuiteFoundation

public struct LogicDiagnostic: Sendable, Hashable, Codable {
    public var severity: DiagnosticSeverity
    public var code: String
    public var message: String
    public var entity: String?
    public var location: LogicSourceSpan?
    public var suggestedActions: [String]

    public init(
        severity: DiagnosticSeverity,
        code: String,
        message: String,
        entity: String? = nil,
        location: LogicSourceSpan? = nil,
        suggestedActions: [String] = []
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.entity = entity
        self.location = location
        self.suggestedActions = suggestedActions
    }

    public var engineDiagnostic: DesignDiagnostic {
        let diagnosticCode: DiagnosticCode
        let invalidCodeDetail: String?
        do {
            diagnosticCode = try DiagnosticCode(rawValue: code)
            invalidCodeDetail = nil
        } catch {
            diagnosticCode = .trusted("logic.invalid-diagnostic-code")
            invalidCodeDetail = "Invalid logic diagnostic code: \(code)"
        }
        let detail = [entity, invalidCodeDetail]
            .compactMap { $0 }
            .joined(separator: "; ")
        let actions = suggestedActions.map {
            SuggestedAction(code: $0, summary: $0)
        }
        return DesignDiagnostic(
            code: diagnosticCode,
            severity: severity,
            summary: message,
            detail: detail.isEmpty ? nil : detail,
            suggestedActions: actions
        )
    }
}
