public struct LogicStorageReservation: ~Copyable {
    let owner: LogicReservationOwner
    let identifier: UInt64
    public let byteCount: UInt64

    init(owner: LogicReservationOwner, identifier: UInt64, byteCount: UInt64) {
        self.owner = owner
        self.identifier = identifier
        self.byteCount = byteCount
    }
}
