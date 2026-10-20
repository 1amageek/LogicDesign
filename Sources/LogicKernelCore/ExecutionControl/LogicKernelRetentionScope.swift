/// A single active, context-authenticated controlled publication scope.
public struct LogicKernelRetentionScope: ~Copyable {
    let owner: LogicReservationOwner
    let identifier: UInt64
    let metadataReservation: UInt64
}
