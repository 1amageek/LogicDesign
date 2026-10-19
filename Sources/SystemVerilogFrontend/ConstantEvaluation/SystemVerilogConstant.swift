import LogicIR
import LogicKernelCore

package struct SystemVerilogConstant: Sendable {
    package let type: SystemVerilogConstantType
    package let value: LogicFourStateVector
    package let origin: LogicKernelSourceRange
}
