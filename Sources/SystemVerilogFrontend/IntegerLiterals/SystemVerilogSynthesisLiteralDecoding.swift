import LogicIR
import LogicKernelCore

public protocol SystemVerilogSynthesisLiteralDecoding: Sendable {
    @available(macOS 26.0, *)
    func decode(_ byteRange: Range<Int>, in source: borrowing LogicSourceDocument,
                context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogSynthesisLiteral
}
