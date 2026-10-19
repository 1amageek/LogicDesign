import CircuiteFoundation
import LogicKernelCore

public struct RTLResolvedProcess: Sendable {
    public enum Control: Sendable {
        case continuous
        case combinational
        case flipFlop(clock: RTLExpressionIndex, edge: BitStateControl.Edge, asynchronousReset: RTLResolvedReset?)
        case latch
        case levelSensitive
    }
    public let id: DesignEntityID
    public let control: Control
    public let body: RTLStatementIndex
    public let origin: LogicKernelSourceRange?
    public init(id: DesignEntityID, control: Control, body: RTLStatementIndex, origin: LogicKernelSourceRange? = nil) {
        self.id = id; self.control = control; self.body = body; self.origin = origin
    }
}
