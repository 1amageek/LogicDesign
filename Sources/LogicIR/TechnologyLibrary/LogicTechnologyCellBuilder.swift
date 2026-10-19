import CircuiteFoundation
import LogicKernelCore

public struct LogicTechnologyCellBuilder: ~Copyable {
    private let id: DesignEntityID
    private let name: String
    private let pinCapacity: Int
    private var pins: [LogicTechnologyPin]

    public init(id: DesignEntityID, name: String, pinCapacity: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) {
        guard !name.isEmpty, pinCapacity > 0 else {
            throw .invalidInput("Cell requires a nonempty name and positive pin capacity")
        }
        try context.require(.edges, amount: UInt64(pinCapacity))
        let payload = UInt64(pinCapacity).multipliedReportingOverflow(by: UInt64(MemoryLayout<LogicTechnologyPin>.stride))
        let metadata = UInt64(MemoryLayout<(DesignEntityID, String, [LogicTechnologyPin], LogicCellStateDefinition?, Double)>.stride)
        let total = payload.partialValue.addingReportingOverflow(metadata)
        guard !payload.overflow, !total.overflow else { throw .invalidInput("Cell capacity overflows") }
        try context.charge(.workUnits, amount: UInt64(name.utf8.count))
        _ = try context.reserveStorage(byteCount: UInt64(name.utf8.count))
        _ = try context.reserveStorage(byteCount: total.partialValue)
        self.id = id; self.name = name; self.pinCapacity = pinCapacity
        pins = []; pins.reserveCapacity(pinCapacity)
    }

    public mutating func append(_ pin: LogicTechnologyPin, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicCellPinIndex {
        try context.checkpoint()
        guard pins.count < pinCapacity else { throw .invalidInput("Cell pin capacity exhausted") }
        guard !pin.name.isEmpty, pin.id != id else { throw .invalidModel("Cell pin name or identity is invalid") }
        guard (pin.direction == .output) == (pin.function != nil) else {
            throw .invalidModel("Only output pins must have a function")
        }
        for existing in pins {
            try context.charge(.workUnits, amount: UInt64(existing.name.utf8.count) + UInt64(pin.name.utf8.count) + 1)
            guard existing.id != pin.id, existing.name != pin.name else {
                throw .invalidModel("Cell pins have duplicate names or identities")
            }
        }
        try context.charge(.workUnits, amount: UInt64(pin.name.utf8.count) + 1)
        _ = try context.reserveStorage(byteCount: UInt64(pin.name.utf8.count))
        try context.charge(.edges)
        let index = LogicCellPinIndex(pins.count)
        pins.append(pin)
        return index
    }

    @available(macOS 26.0, *)
    public consuming func finish(area: Double, state: LogicCellStateDefinition? = nil,
                                 context: inout LogicKernelContext) throws(LogicKernelError) -> LogicTechnologyCell {
        try context.checkpoint()
        guard !pins.isEmpty, area.isFinite, area >= 0 else { throw .invalidModel("Cell pins or area are invalid") }
        let slotCount = pins.count.addingReportingOverflow(state == nil ? 0 : 1)
        guard !slotCount.overflow else { throw .invalidModel("Cell function input count overflows") }
        var outputs = 0
        for pin in pins {
            try context.charge(.workUnits)
            if let function = pin.function {
                outputs += 1
                try validate(function, slotCount: slotCount.partialValue, context: &context)
            }
        }
        guard outputs > 0 else { throw .invalidModel("Cell has no functional output") }
        if let state {
            guard isInput(state.control.pin) else { throw .invalidModel("State control is not an input pin") }
            if let reset = state.asynchronousReset {
                guard isInput(reset.pin), reset.pin != state.control.pin else {
                    throw .invalidModel("Asynchronous reset is not a distinct input pin")
                }
            }
            try validate(state.nextState, slotCount: slotCount.partialValue, context: &context)
            try context.charge(.states)
        }
        try context.charge(.nodes)
        return LogicTechnologyCell(storage: .init(id: id, name: name, pins: pins, state: state, area: area))
    }

    private borrowing func isInput(_ index: LogicCellPinIndex) -> Bool {
        index.rawValue >= 0 && index.rawValue < pins.count && pins[index.rawValue].direction == .input
    }

    @available(macOS 26.0, *)
    private borrowing func validate(_ function: LogicBooleanFunction, slotCount: Int,
                                    context: inout LogicKernelContext) throws(LogicKernelError) {
        guard function.inputCount == slotCount else { throw .invalidModel("Cell function input namespace does not match pins and state") }
        try function.withOperations { operations throws(LogicKernelError) in
            for index in operations.indices {
                try context.charge(.workUnits)
                let operation = operations[index]
                if case .input(let slot) = operation, slot < pins.count, pins[slot].direction != .input {
                    throw .invalidModel("Cell function references an output pin")
                }
            }
        }
    }
}
