import LogicKernelCore

public struct LogicSourceBundle: Sendable {
    private final class Storage: Sendable {
        let documents: [LogicSourceDocument]
        init(documents: consuming [LogicSourceDocument]) { self.documents = documents }
    }
    private let storage: Storage
    public var count: Int { storage.documents.count }

    public init(documents: consuming [LogicSourceDocument], context: inout LogicKernelContext)
        throws(LogicKernelError) {
        guard !documents.isEmpty else { throw .invalidInput("Source bundle is empty") }
        let size = UInt64(documents.count).multipliedReportingOverflow(by: UInt64(MemoryLayout<LogicSourceDocument>.stride))
        guard !size.overflow else { throw .invalidInput("Source bundle storage overflow") }
        _ = try context.reserveStorage(byteCount: size.partialValue)
        let scratch = try context.reserveStorage(byteCount: size.partialValue)
        do { try Self.validateNames(documents, context: &context) }
        catch { try context.releaseStorage(scratch); throw error }
        try context.releaseStorage(scratch)
        storage = Storage(documents: documents)
    }

    private static func validateNames(_ documents: borrowing [LogicSourceDocument], context: inout LogicKernelContext)
        throws(LogicKernelError) {
        var names = Set<String>(); names.reserveCapacity(documents.count)
        for index in documents.indices {
            try context.charge(.workUnits, amount: UInt64(documents[index].logicalName.utf8.count) + 1)
            guard names.insert(documents[index].logicalName).inserted else {
                throw .invalidInput("Duplicate logical source name")
            }
        }
    }

    public borrowing func document(at index: Int) throws(LogicKernelError) -> LogicSourceDocument {
        guard storage.documents.indices.contains(index) else { throw .invalidInput("Source index outside bundle") }
        return storage.documents[index]
    }

    @available(macOS 26.0, *)
    public borrowing func withDocuments<Result, Failure: Error>(
        _ body: (borrowing Span<LogicSourceDocument>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage; let documents = owner.documents
        defer { withExtendedLifetime(owner) {} }
        return try body(documents.span)
    }
}
