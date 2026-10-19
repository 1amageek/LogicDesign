import LogicKernelCore

public enum StructuralVerilogSourceError: Error, Sendable {
    case malformed(byteRange: Range<Int>, reason: String)
    case unsupported(byteRange: Range<Int>, semantic: String)
    case kernel(LogicKernelError)
}
