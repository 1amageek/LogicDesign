import Foundation

public struct GateNetlistParseResult: Sendable, Hashable, Codable {
    public var design: GateDesign?
    public var diagnostics: [LogicDiagnostic]

    public init(design: GateDesign?, diagnostics: [LogicDiagnostic] = []) {
        self.design = design
        self.diagnostics = diagnostics
    }

    public var isValid: Bool {
        design != nil && !diagnostics.contains { $0.severity == .error }
    }
}
