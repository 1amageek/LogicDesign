import Foundation
import LogicIR

public protocol SystemVerilogLexing: Sendable {
    func lex(_ source: SystemVerilogSourceUnit) -> SystemVerilogLexResult
}
