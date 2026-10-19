import LogicIR
import LogicKernelCore

package struct SystemVerilogConstantType: Sendable {
    package let width: LogicBitWidth
    package let isSigned: Bool
    package let isIndefinite: Bool
    package let dimensions: [SystemVerilogPackedDimension]
    package init(width: Int, signed: Bool = false, indefinite: Bool = false,
                 dimensions: consuming [SystemVerilogPackedDimension] = []) throws(LogicKernelError) {
        self.width = try LogicBitWidth(width); isSigned = signed
        isIndefinite = indefinite; self.dimensions = dimensions
    }
}
