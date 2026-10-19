import LogicIR
import LogicKernelCore

package struct SystemVerilogDynamicSelection: Sendable {
    package let rightBound: Int
    package let descending: Bool
    package let adjustment: Int
    package let unit: Int

    package func offsetType(for input: WordLogicType) throws(LogicKernelError) -> WordLogicType {
        let sourceWidth = input.width.value.addingReportingOverflow(input.isSigned ? 0 : 1)
        let unitBits = Int.bitWidth - unit.leadingZeroBitCount
        let width = max(sourceWidth.partialValue, Int.bitWidth).addingReportingOverflow(2 + unitBits)
        guard unit > 0, !sourceWidth.overflow, !width.overflow else { throw .invalidInput("Selection offset width overflow") }
        return WordLogicType(width: try LogicBitWidth(width.partialValue), isSigned: true)
    }
}
