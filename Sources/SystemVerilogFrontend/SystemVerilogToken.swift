import Foundation
import LogicIR

public struct SystemVerilogToken: Sendable, Hashable, Codable {
    public var kind: SystemVerilogTokenKind
    public var lexeme: String
    public var span: LogicSourceSpan

    public init(kind: SystemVerilogTokenKind, lexeme: String, span: LogicSourceSpan) {
        self.kind = kind
        self.lexeme = lexeme
        self.span = span
    }
}
