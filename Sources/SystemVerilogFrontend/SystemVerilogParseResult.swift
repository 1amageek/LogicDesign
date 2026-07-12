import Foundation
import LogicIR

public struct SystemVerilogParseResult: Sendable, Hashable, Codable {
    public var design: RTLDesign?
    public var diagnostics: [LogicDiagnostic]
    public var unsupportedSemantics: Bool

    public init(
        design: RTLDesign?,
        diagnostics: [LogicDiagnostic] = [],
        unsupportedSemantics: Bool = false
    ) {
        self.design = design
        self.diagnostics = diagnostics
        self.unsupportedSemantics = unsupportedSemantics
    }

    public var isBlocked: Bool {
        unsupportedSemantics
    }
}
