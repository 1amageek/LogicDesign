import Foundation
import LogicIR
import LogicDesignSerialization

public struct SystemVerilogLexResult: Sendable, Hashable, Codable {
    public var tokens: [SystemVerilogToken]
    public var diagnostics: [LogicDiagnostic]

    public init(tokens: [SystemVerilogToken], diagnostics: [LogicDiagnostic] = []) {
        self.tokens = tokens
        self.diagnostics = diagnostics
    }
}
