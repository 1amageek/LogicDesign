import CircuiteFoundation
import LogicKernelCore

public struct LogicTechnologyLibraryBuilder: ~Copyable {
    private let cellCapacity: Int
    private let totalPinCapacity: Int
    private var pinCount = 0
    private var cells: [LogicTechnologyCell]
    private var identifiers: Set<DesignEntityID>
    private var names: Set<String>

    public init(cellCapacity: Int, totalPinCapacity: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        guard cellCapacity > 0, totalPinCapacity >= 0 else { throw .invalidInput("Invalid library capacities") }
        try context.require(.nodes, amount: UInt64(cellCapacity))
        try context.require(.edges, amount: UInt64(totalPinCapacity))
        let count = cellCapacity.addingReportingOverflow(totalPinCapacity)
        guard !count.overflow else { throw .invalidInput("Library identity capacity overflows") }
        let cellsAndNames = UInt64(cellCapacity).multipliedReportingOverflow(
            by: UInt64(MemoryLayout<LogicTechnologyCell>.stride + MemoryLayout<String>.stride))
        let ids = UInt64(count.partialValue).multipliedReportingOverflow(by: UInt64(MemoryLayout<DesignEntityID>.stride))
        let payload = cellsAndNames.partialValue.addingReportingOverflow(ids.partialValue)
        let total = payload.partialValue.addingReportingOverflow(UInt64(MemoryLayout<(ArtifactID, [LogicTechnologyCell])>.stride))
        guard !cellsAndNames.overflow, !ids.overflow, !payload.overflow, !total.overflow else {
            throw .invalidInput("Library capacity overflows")
        }
        _ = try context.reserveStorage(byteCount: total.partialValue)
        self.cellCapacity = cellCapacity; self.totalPinCapacity = totalPinCapacity
        cells = []; cells.reserveCapacity(cellCapacity)
        identifiers = []; identifiers.reserveCapacity(count.partialValue)
        names = []; names.reserveCapacity(cellCapacity)
    }

    @available(macOS 26.0, *)
    public mutating func append(_ cell: LogicTechnologyCell, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicCellIndex {
        try context.charge(.workUnits, amount: UInt64(cell.name.utf8.count) + 1)
        guard cells.count < cellCapacity, cell.pinCount <= totalPinCapacity - pinCount else {
            throw .invalidInput("Library cell or pin capacity exhausted")
        }
        guard !identifiers.contains(cell.id), !names.contains(cell.name) else {
            throw .invalidModel("Library cell identity or name is duplicated")
        }
        try cell.withPins { pins throws(LogicKernelError) in
            for index in pins.indices {
                try context.charge(.workUnits, amount: 2)
                let pin = pins[index]
                guard !identifiers.contains(pin.id) else { throw .invalidModel("Library pin identity is duplicated") }
            }
        }
        // Complete all fallible checks before mutating membership tables.
        let index = LogicCellIndex(cells.count)
        identifiers.insert(cell.id); names.insert(cell.name)
        cell.withPins { pins in for index in pins.indices { identifiers.insert(pins[index].id) } }
        pinCount += cell.pinCount
        cells.append(cell)
        return index
    }

    public consuming func finish(source: ArtifactID, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicTechnologyLibrary {
        try context.checkpoint()
        guard !cells.isEmpty else { throw .invalidModel("Library has no eligible cells") }
        return LogicTechnologyLibrary(storage: .init(source: source, cells: cells))
    }
}
