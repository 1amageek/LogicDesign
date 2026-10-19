import LogicKernelCore

public struct LogicFourStateVector: Sendable, Hashable {
    private final class Storage: Sendable {
        let width: LogicBitWidth
        let values: [UInt64]
        let unknowns: [UInt64]

        init(width: LogicBitWidth, values: consuming [UInt64], unknowns: consuming [UInt64]) {
            self.width = width
            self.values = values
            self.unknowns = unknowns
        }
    }

    private let storage: Storage
    public var width: LogicBitWidth { storage.width }
    public var isTwoState: Bool { storage.unknowns.allSatisfy { $0 == 0 } }

    public init(
        width: LogicBitWidth,
        valueWords: consuming [UInt64],
        unknownWords: consuming [UInt64]
    ) throws(LogicKernelError) {
        guard valueWords.count == width.wordCount, unknownWords.count == width.wordCount else {
            throw .invalidInput("Bit-plane word count does not match width")
        }
        guard valueWords[width.wordCount - 1] & ~width.tailMask == 0,
              unknownWords[width.wordCount - 1] & ~width.tailMask == 0 else {
            throw .invalidInput("Unused bit-plane tail bits must be zero")
        }
        storage = Storage(width: width, values: valueWords, unknowns: unknownWords)
    }

    public init(repeating bit: LogicBit, width: LogicBitWidth, context: inout LogicKernelContext)
        throws(LogicKernelError) {
        try context.observeBitWidth(UInt64(width.value))
        let bytes = UInt64(width.wordCount) * 16
        // Published value storage is retained and charged for the whole invocation.
        _ = try context.reserveStorage(byteCount: bytes)
        var values = [UInt64](repeating: bit.rawValue & 1 == 0 ? 0 : .max, count: width.wordCount)
        var unknowns = [UInt64](repeating: bit.rawValue & 2 == 0 ? 0 : .max, count: width.wordCount)
        values[width.wordCount - 1] &= width.tailMask
        unknowns[width.wordCount - 1] &= width.tailMask
        try self.init(width: width, valueWords: values, unknownWords: unknowns)
    }

    public borrowing func bit(at index: Int) throws(LogicKernelError) -> LogicBit {
        guard index >= 0 && index < width.value else {
            throw .invalidInput("Bit index is outside the vector")
        }
        let offset = index % 64
        let value = UInt8((storage.values[index / 64] >> offset) & 1)
        let unknown = UInt8((storage.unknowns[index / 64] >> offset) & 1)
        return LogicBit(rawValue: value | (unknown << 1))!
    }

    @available(macOS 26.0, *)
    public borrowing func withPlanes<Result, Failure: Error>(
        _ body: (borrowing Span<UInt64>, borrowing Span<UInt64>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let retainedOwner = storage
        let values = retainedOwner.values
        let unknowns = retainedOwner.unknowns
        defer { withExtendedLifetime(retainedOwner) {} }
        return try body(values.span, unknowns.span)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.width == rhs.width && lhs.storage.values == rhs.storage.values
            && lhs.storage.unknowns == rhs.storage.unknowns
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(storage.values)
        hasher.combine(storage.unknowns)
    }
}
