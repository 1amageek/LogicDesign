import Synchronization

@available(macOS 15.0, *)
public final class LogicCancellationSource: Sendable, LogicRunControlling {
    private let state = Mutex(false)

    public init() {}

    public func cancel() {
        state.withLock { $0 = true }
    }

    public var isCancelled: Bool {
        state.withLock { $0 }
    }

    public func checkpoint() throws(LogicKernelError) {
        if isCancelled { throw .cancelled }
    }
}
