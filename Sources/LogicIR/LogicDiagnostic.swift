import Foundation
import XcircuitePackage

public struct LogicDiagnostic: Sendable, Hashable, Codable {
    public var severity: XcircuiteEngineDiagnosticSeverity
    public var code: String
    public var message: String
    public var entity: String?
    public var location: LogicSourceSpan?
    public var suggestedActions: [String]

    public init(
        severity: XcircuiteEngineDiagnosticSeverity,
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

    public var engineDiagnostic: XcircuiteEngineDiagnostic {
        XcircuiteEngineDiagnostic(
            severity: severity,
            code: code,
            message: message,
            entity: entity,
            suggestedActions: suggestedActions
        )
    }
}
