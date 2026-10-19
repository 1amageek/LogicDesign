import LogicKernelCore

public struct LogicBitWidth: Sendable, Hashable {
    public let value: Int

    public init(_ value: Int) throws(LogicKernelError) {
        guard value > 0 else { throw .invalidInput("Bit width must be positive") }
        self.value = value
    }

    public var wordCount: Int { value / 64 + (value % 64 == 0 ? 0 : 1) }
    public var tailMask: UInt64 {
        value % 64 == 0 ? .max : (UInt64(1) << (value % 64)) - 1
    }
}
