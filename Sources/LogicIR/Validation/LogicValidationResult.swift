import CircuiteFoundation

public struct LogicValidationResult: Sendable, Hashable {
    public var isValid: Bool
    public var diagnostics: [LogicDiagnostic]

    public init(isValid: Bool, diagnostics: [LogicDiagnostic] = []) {
        self.isValid = isValid
        self.diagnostics = diagnostics
    }

    public var hasErrors: Bool {
        diagnostics.contains { $0.severity == .error }
    }
}
