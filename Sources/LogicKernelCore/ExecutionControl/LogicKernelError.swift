import CircuiteFoundation

public enum LogicKernelError: Error, Sendable, Equatable {
    case invalidInput(String)
    case invalidModel(String)
    case unsupported(String)
    case sourceFailure(code: DiagnosticCode, source: LogicKernelSourceRange, message: String)
    case resourceLimit(resource: LogicResource, limit: UInt64, requested: UInt64?)
    case cancelled
    case deadlineExceeded
}
