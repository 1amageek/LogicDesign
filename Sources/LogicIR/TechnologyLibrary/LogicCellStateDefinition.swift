public struct LogicCellStateDefinition: Sendable {
    public enum Control: Sendable, Equatable {
        case flipFlop(clock: LogicCellPinIndex, risingEdge: Bool)
        case latch(gate: LogicCellPinIndex, activeHigh: Bool)

        public var pin: LogicCellPinIndex {
            switch self {
            case .flipFlop(let pin, _), .latch(let pin, _): pin
            }
        }
    }
    public struct AsynchronousReset: Sendable, Equatable {
        public let pin: LogicCellPinIndex
        public let activeHigh: Bool
        public let value: Bool
        public init(pin: LogicCellPinIndex, activeHigh: Bool, value: Bool) {
            self.pin = pin; self.activeHigh = activeHigh; self.value = value
        }
    }

    public let control: Control
    public let nextState: LogicBooleanFunction
    public let asynchronousReset: AsynchronousReset?

    public init(control: Control, nextState: LogicBooleanFunction, asynchronousReset: AsynchronousReset? = nil) {
        self.control = control; self.nextState = nextState; self.asynchronousReset = asynchronousReset
    }
}
