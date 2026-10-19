import Foundation
import LogicIR
import LogicDesignSerialization

public struct PowerIntentValidationResult: Sendable, Hashable, Codable {
    public var isValid: Bool
    public var diagnostics: [LogicDiagnostic]

    public init(isValid: Bool, diagnostics: [LogicDiagnostic] = []) {
        self.isValid = isValid
        self.diagnostics = diagnostics
    }
}
