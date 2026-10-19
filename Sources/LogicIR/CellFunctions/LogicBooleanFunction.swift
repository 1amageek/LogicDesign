public struct LogicBooleanFunction: Sendable {
    public static let schemaVersion = 1

    internal final class Storage: Sendable {
        let inputCount: Int
        let operations: [LogicBooleanOperation]
        let output: LogicBooleanNodeIndex

        init(inputCount: Int, operations: consuming [LogicBooleanOperation], output: LogicBooleanNodeIndex) {
            self.inputCount = inputCount; self.operations = operations; self.output = output
        }
    }

    private let storage: Storage
    internal init(storage: Storage) { self.storage = storage }
    public var inputCount: Int { storage.inputCount }
    public var nodeCount: Int { storage.operations.count }
    public var output: LogicBooleanNodeIndex { storage.output }

    @available(macOS 26.0, *)
    public borrowing func withOperations<Result, Failure: Error>(
        _ body: (borrowing Span<LogicBooleanOperation>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage
        let operations = owner.operations
        defer { withExtendedLifetime(owner) {} }
        return try body(operations.span)
    }
}
