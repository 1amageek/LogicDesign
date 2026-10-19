public struct LogicKernelContext: ~Copyable {
    public let limits: LogicKernelLimits
    private let control: any LogicRunControlling
    private let reservationOwner = LogicReservationOwner()
    private var counters: [LogicResource: UInt64] = [:]
    private var peakStorage: UInt64 = 0
    private var nextReservation: UInt64 = 0
    private var reservations: [UInt64: UInt64] = [:]

    public init(limits: LogicKernelLimits, control: any LogicRunControlling) {
        self.limits = limits
        self.control = control
    }

    public var usage: LogicKernelUsage {
        LogicKernelUsage(counters: counters, peakManagedStorageBytes: peakStorage)
    }

    public borrowing func checkpoint() throws(LogicKernelError) {
        try control.checkpoint()
    }

    public mutating func observeBitWidth(_ width: UInt64) throws(LogicKernelError) {
        try checkpoint()
        guard width > 0 else { throw .invalidInput("Bit width must be positive") }
        try require(.bitWidth, amount: width)
        counters[.bitWidth] = max(counters[.bitWidth, default: 0], width)
    }

    public mutating func charge(_ resource: LogicResource, amount: UInt64 = 1)
        throws(LogicKernelError) {
        try checkpoint()
        guard resource != .managedStorageBytes && resource != .bitWidth else {
            throw .invalidInput("Use a storage reservation or bit-width observation")
        }
        let updated = try checkedCharge(resource, amount: amount)
        counters[resource] = updated
    }

    public mutating func reserveStorage(byteCount: UInt64)
        throws(LogicKernelError) -> LogicStorageReservation {
        try checkpoint()
        let receiptCount = try checkedCharge(.storageReservations, amount: 1)
        let storage = try checkedCharge(.managedStorageBytes, amount: byteCount)
        let allocations = try checkedCharge(.allocationBytes, amount: byteCount)
        let identifier = nextReservation.addingReportingOverflow(1)
        guard !identifier.overflow else {
            throw .invalidInput("Storage reservation identity exhausted")
        }
        // Commit every accounting mutation only after all checks have passed.
        counters[.storageReservations] = receiptCount
        counters[.managedStorageBytes] = storage
        counters[.allocationBytes] = allocations
        peakStorage = max(peakStorage, storage)
        nextReservation = identifier.partialValue
        reservations[nextReservation] = byteCount
        return LogicStorageReservation(
            owner: reservationOwner, identifier: nextReservation, byteCount: byteCount
        )
    }

    public mutating func releaseStorage(_ reservation: consuming LogicStorageReservation)
        throws(LogicKernelError) {
        guard reservation.owner === reservationOwner,
              reservations[reservation.identifier] == reservation.byteCount else {
            throw .invalidInput("Storage reservation belongs to a different context")
        }
        reservations.removeValue(forKey: reservation.identifier)
        counters[.managedStorageBytes, default: 0] -= reservation.byteCount
    }

    public borrowing func require(_ resource: LogicResource, amount: UInt64)
        throws(LogicKernelError) {
        guard amount <= limits[resource] else {
            throw .resourceLimit(resource: resource, limit: limits[resource], requested: amount)
        }
    }

    private borrowing func checkedCharge(_ resource: LogicResource, amount: UInt64)
        throws(LogicKernelError) -> UInt64 {
        let updated = counters[resource, default: 0].addingReportingOverflow(amount)
        guard !updated.overflow else {
            throw .resourceLimit(resource: resource, limit: limits[resource], requested: nil)
        }
        try require(resource, amount: updated.partialValue)
        return updated.partialValue
    }
}
