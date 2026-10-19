import CircuiteFoundation
import LogicKernelCore

public struct LogicSourceDocument: Sendable {
    private final class Storage: Sendable {
        let bytes: [UInt8]
        init(bytes: consuming [UInt8]) { self.bytes = bytes }
    }
    public let logicalName: String
    public let artifactID: ArtifactID
    private let storage: Storage
    public var byteCount: Int { storage.bytes.count }

    /// The host must verify the digest against these exact bytes before construction.
    public init(logicalName: String, artifactID: ArtifactID, bytes: consuming [UInt8],
                context: inout LogicKernelContext) throws(LogicKernelError) {
        guard !logicalName.isEmpty, artifactID.byteCount == UInt64(bytes.count) else {
            throw .invalidInput("Source name is empty or artifact byte count differs")
        }
        let size = UInt64(bytes.count).addingReportingOverflow(UInt64(logicalName.utf8.count))
        guard !size.overflow else { throw .invalidInput("Source storage overflow") }
        _ = try context.reserveStorage(byteCount: size.partialValue)
        try context.charge(.expansion, amount: UInt64(bytes.count))
        try Self.validateUTF8(bytes, context: &context)
        self.logicalName = logicalName; self.artifactID = artifactID
        storage = Storage(bytes: bytes)
    }

    @available(macOS 26.0, *)
    public borrowing func withBytes<Result, Failure: Error>(
        _ body: (borrowing Span<UInt8>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage; let bytes = owner.bytes
        defer { withExtendedLifetime(owner) {} }
        return try body(bytes.isEmpty ? Span() : bytes.span)
    }

    package static func validateUTF8(_ bytes: borrowing [UInt8], context: inout LogicKernelContext)
        throws(LogicKernelError) {
        var index = 0
        while index < bytes.count {
            let first = bytes[index]
            let count: Int
            let minimumSecond: UInt8
            let maximumSecond: UInt8
            switch first {
            case 0...0x7f: count = 1; minimumSecond = 0; maximumSecond = 0
            case 0xc2...0xdf: count = 2; minimumSecond = 0x80; maximumSecond = 0xbf
            case 0xe0: count = 3; minimumSecond = 0xa0; maximumSecond = 0xbf
            case 0xe1...0xec, 0xee...0xef: count = 3; minimumSecond = 0x80; maximumSecond = 0xbf
            case 0xed: count = 3; minimumSecond = 0x80; maximumSecond = 0x9f
            case 0xf0: count = 4; minimumSecond = 0x90; maximumSecond = 0xbf
            case 0xf1...0xf3: count = 4; minimumSecond = 0x80; maximumSecond = 0xbf
            case 0xf4: count = 4; minimumSecond = 0x80; maximumSecond = 0x8f
            default: throw .invalidInput("Invalid source UTF-8 leading byte")
            }
            try context.charge(.workUnits, amount: UInt64(count))
            guard count <= bytes.count - index else { throw .invalidInput("Truncated source UTF-8") }
            if count > 1 {
                guard bytes[index + 1] >= minimumSecond, bytes[index + 1] <= maximumSecond else {
                    throw .invalidInput("Invalid source UTF-8 scalar")
                }
                for offset in 2..<count {
                    guard bytes[index + offset] >= 0x80, bytes[index + offset] <= 0xbf else {
                        throw .invalidInput("Invalid source UTF-8 continuation")
                    }
                }
            }
            index += count
        }
    }
}
