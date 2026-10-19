import LogicIR
import LogicKernelCore

public protocol SystemVerilogElaborating: Sendable {
    @available(macOS 26.0, *)
    func elaborate(_ sources: borrowing LogicSourceBundle, options: borrowing SystemVerilogElaborationOptions,
                   context: inout LogicKernelContext) throws(LogicKernelError) -> ElaboratedRTL
}
