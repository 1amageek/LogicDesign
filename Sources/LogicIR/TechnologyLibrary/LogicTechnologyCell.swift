import CircuiteFoundation
import LogicKernelCore

public struct LogicTechnologyCell: Sendable {
    public static let schemaVersion = 1
    internal final class Storage: Sendable {
        let id: DesignEntityID
        let name: String
        let pins: [LogicTechnologyPin]
        let state: LogicCellStateDefinition?
        let area: Double
        init(id: DesignEntityID, name: String, pins: consuming [LogicTechnologyPin],
             state: LogicCellStateDefinition?, area: Double) {
            self.id = id; self.name = name; self.pins = pins; self.state = state; self.area = area
        }
    }
    private let storage: Storage
    internal init(storage: Storage) { self.storage = storage }
    public var id: DesignEntityID { storage.id }
    public var name: String { storage.name }
    public var pinCount: Int { storage.pins.count }
    public var state: LogicCellStateDefinition? { storage.state }
    public var area: Double { storage.area }

    public borrowing func pin(at index: LogicCellPinIndex) throws(LogicKernelError) -> LogicTechnologyPin {
        guard index.rawValue >= 0, index.rawValue < storage.pins.count else {
            throw .invalidInput("Cell pin index is outside the validated table")
        }
        return storage.pins[index.rawValue]
    }

    @available(macOS 26.0, *)
    public borrowing func withPins<Result, Failure: Error>(
        _ body: (borrowing Span<LogicTechnologyPin>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage
        let pins = owner.pins
        defer { withExtendedLifetime(owner) {} }
        return try body(pins.span)
    }
}
