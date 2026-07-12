import Foundation
import LogicIR

public struct PowerIntentParseResult: Sendable, Hashable, Codable {
    public var design: PowerIntentDesign?
    public var diagnostics: [LogicDiagnostic]
    public var unsupportedSemantics: Bool

    public init(
        design: PowerIntentDesign?,
        diagnostics: [LogicDiagnostic] = [],
        unsupportedSemantics: Bool = false
    ) {
        self.design = design
        self.diagnostics = diagnostics
        self.unsupportedSemantics = unsupportedSemantics
    }
}
