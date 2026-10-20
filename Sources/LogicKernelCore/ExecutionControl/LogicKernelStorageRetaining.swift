/// An external storage lease. Last-owner destruction refunds live bytes only.
/// Destruction must neither checkpoint nor throw; cumulative charges are retained.
public protocol LogicKernelStorageRetaining: AnyObject, Sendable {}
