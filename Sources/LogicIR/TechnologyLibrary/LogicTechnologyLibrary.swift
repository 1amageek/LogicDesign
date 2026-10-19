import CircuiteFoundation
import LogicKernelCore

public struct LogicTechnologyLibrary: Sendable {
    public static let schemaVersion = 1
    internal final class Storage: Sendable {
        let source: ArtifactID
        let cells: [LogicTechnologyCell]
        init(source: ArtifactID, cells: consuming [LogicTechnologyCell]) { self.source = source; self.cells = cells }
    }
    private let storage: Storage
    internal init(storage: Storage) { self.storage = storage }
    public var source: ArtifactID { storage.source }
    public var cellCount: Int { storage.cells.count }

    internal borrowing func sharesStorage(with other: borrowing LogicTechnologyLibrary) -> Bool {
        storage === other.storage
    }

    public borrowing func cell(at index: LogicCellIndex) throws(LogicKernelError) -> LogicTechnologyCell {
        guard index.rawValue >= 0, index.rawValue < storage.cells.count else {
            throw .invalidInput("Library cell index is outside the validated table")
        }
        return storage.cells[index.rawValue]
    }

    @available(macOS 26.0, *)
    public borrowing func withCells<Result, Failure: Error>(
        _ body: (borrowing Span<LogicTechnologyCell>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage
        let cells = owner.cells
        defer { withExtendedLifetime(owner) {} }
        return try body(cells.span)
    }
}
