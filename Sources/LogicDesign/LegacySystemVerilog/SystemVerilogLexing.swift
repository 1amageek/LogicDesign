import Foundation
import LogicIR
import LogicDesignSerialization

public protocol SystemVerilogLexing: Sendable {
    func lex(_ source: SystemVerilogSourceUnit) -> SystemVerilogLexResult
}
