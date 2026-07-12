import Foundation
import LogicIR

public struct SystemVerilogLexResult: Sendable, Hashable, Codable {
    public var tokens: [SystemVerilogToken]
    public var diagnostics: [LogicDiagnostic]

    public init(tokens: [SystemVerilogToken], diagnostics: [LogicDiagnostic] = []) {
        self.tokens = tokens
        self.diagnostics = diagnostics
    }
}
