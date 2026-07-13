import Foundation

public struct RTLHierarchyElaborationResult: Sendable, Hashable, Codable {
    public var design: RTLDesign?
    public var diagnostics: [LogicDiagnostic]

    public init(
        design: RTLDesign?,
        diagnostics: [LogicDiagnostic] = []
    ) {
        self.design = design
        self.diagnostics = diagnostics
    }

    public var isComplete: Bool {
        design != nil && !diagnostics.contains { $0.severity == .error }
    }
}
