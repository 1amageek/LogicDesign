import Foundation
import LogicKernelCore

@available(macOS 26.0, *)
public protocol StructuralVerilogSourceDecoding: Sendable {
    func decodeSource(_ data: Data, top: String, context: inout LogicKernelContext)
        throws(StructuralVerilogSourceError) -> StructuralVerilogSource
}
