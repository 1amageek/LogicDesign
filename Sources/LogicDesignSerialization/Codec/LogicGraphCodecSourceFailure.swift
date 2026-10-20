import LogicKernelCore

/// A source/semantic cause plus its pre-admitted logical payload lifetime.
/// Keep the wrapper or retention anchor with every extracted cause copy.
public struct LogicGraphCodecSourceFailure: Error {
    public let cause: any Error
    public let retention: LogicKernelRetention
    internal init(cause: any Error, retention: LogicKernelRetention) {
        self.cause = cause; self.retention = retention
    }
    internal static func rethrow(_ error: any Error, scope: borrowing LogicKernelRetentionScope,
        context: inout LogicKernelContext) throws -> Never {
        if let kernel = error as? LogicKernelError {
            switch kernel {
            case .resourceLimit, .cancelled, .deadlineExceeded, .externalAccountingFailure:
                try context.discardRetentionScope(scope)
                throw kernel
            default: break
            }
        }
        let retained = try context.retainFailureScope(scope)
        throw Self(cause: error, retention: retained)
    }
}
