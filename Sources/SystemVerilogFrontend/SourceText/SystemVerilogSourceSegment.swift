import LogicKernelCore
import LogicIR

package struct SystemVerilogSourceSegment: Sendable {
    package let textRange: Range<Int>
    package let document: LogicSourceDocument
    package let origin: LogicKernelSourceRange
    package let isExact: Bool

    package init(textRange: Range<Int>, document: borrowing LogicSourceDocument,
                 origin: LogicKernelSourceRange, isExact: Bool) {
        self.textRange = textRange; self.document = copy document
        self.origin = origin; self.isExact = isExact
    }
}
