import LogicIR
import LogicKernelCore

public protocol SystemVerilogTokenizing: Sendable {
    @available(macOS 26.0, *)
    func tokenize(_ source: borrowing LogicSourceDocument, maximumTokens: Int,
                  context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogTokenStream
}
