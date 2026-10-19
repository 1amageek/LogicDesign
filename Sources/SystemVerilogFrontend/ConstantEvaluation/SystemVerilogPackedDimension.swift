import LogicKernelCore

package struct SystemVerilogPackedDimension: Sendable, Equatable {
    package let left: Int
    package let right: Int
    package let count: Int
    package init(left: Int, right: Int) throws(LogicKernelError) {
        let difference = max(left, right).subtractingReportingOverflow(min(left, right))
        let count = difference.partialValue.addingReportingOverflow(1)
        guard !difference.overflow, !count.overflow else { throw .invalidInput("Packed dimension size overflow") }
        self.left = left; self.right = right; self.count = count.partialValue
    }
    package func offset(of index: Int) throws(LogicKernelError) -> Int {
        guard index >= min(left, right), index <= max(left, right) else {
            throw .invalidInput("Packed selection is outside its declared range")
        }
        return left >= right ? index - right : right - index
    }
}
