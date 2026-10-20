/// Invocation-owned forwarding to a shared external budget.
public protocol LogicKernelAccounting: AnyObject, Sendable {
    func observeBitWidth(_ width: UInt64) throws(LogicKernelError)
    func charge(_ resource: LogicResource, amount: UInt64) throws(LogicKernelError)
    /// Atomically admits live storage, cumulative allocation and one reservation.
    /// Refusal must leave the external accountant unchanged.
    func reserveStorage(byteCount: UInt64) throws(LogicKernelError) -> any LogicKernelStorageRetaining
}
