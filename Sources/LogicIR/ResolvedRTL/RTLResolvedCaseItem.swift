import LogicKernelCore

public struct RTLResolvedCaseItem: Sendable {
    public let matches: Range<Int>
    public let body: RTLStatementIndex
    public let origin: LogicKernelSourceRange?
    internal init(matches: Range<Int>, body: RTLStatementIndex, origin: LogicKernelSourceRange?) {
        self.matches = matches; self.body = body; self.origin = origin
    }
}
