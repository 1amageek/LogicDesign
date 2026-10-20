public struct LogicKernelContext: ~Copyable {
    public let limits: LogicKernelLimits
    private let control: any LogicRunControlling
    private let accounting: (any LogicKernelAccounting)?
    private let reservationOwner = LogicReservationOwner()
    private var counters: [LogicResource: UInt64] = [:]
    private var peakStorage: UInt64 = 0
    private var nextReservation: UInt64 = 0
    private var reservations: [UInt64: UInt64] = [:]

    private var externalReservations: [UInt64: LogicKernelExternalReservation] = [:]
    private var scopedReservations: [UInt64: LogicKernelExternalReservation] = [:]
    // Dictionaries precede their backing leases so pinned-toolchain destruction
    // keeps the backing admitted until its stored entries have been destroyed.
    private var reservationBacking: (any LogicKernelStorageRetaining)?
    private var externalBacking: (any LogicKernelStorageRetaining)?
    private var scopedBacking: (any LogicKernelStorageRetaining)?
    private var reservationCapacity = 0
    private var externalCapacity = 0
    private var scopedCapacity = 0
    private var scopedBytes: UInt64 = 0
    private var activeScope: UInt64?

    public var checkpointControl: any LogicRunControlling { control }

    public var hasExternalAccounting: Bool { accounting != nil }

    public borrowing func requireAccounting(expected: any LogicKernelAccounting) throws(LogicKernelError) {
        guard let accounting, accounting === expected else {
            throw .invalidInput("The installed external accountant is not the expected owner")
        }
    }

    public init(limits: LogicKernelLimits, control: any LogicRunControlling) {
        self.limits = limits
        self.control = control
        self.accounting = nil
    }

    public init(limits: LogicKernelLimits, control: any LogicRunControlling,
                accounting: any LogicKernelAccounting) {
        self.limits = limits
        self.control = control
        self.accounting = accounting
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
        try accounting?.observeBitWidth(width)
        if accounting != nil { try checkpoint() }
        counters[.bitWidth] = max(counters[.bitWidth, default: 0], width)
    }

    public mutating func charge(_ resource: LogicResource, amount: UInt64 = 1)
        throws(LogicKernelError) {
        try checkpoint()
        guard resource != .managedStorageBytes && resource != .bitWidth else {
            throw .invalidInput("Use a storage reservation or bit-width observation")
        }
        let updated = try checkedCharge(resource, amount: amount)
        try accounting?.charge(resource, amount: amount)
        if accounting != nil { try checkpoint() }
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
        let scopedTotal = scopedBytes.addingReportingOverflow(byteCount)
        guard activeScope == nil || !scopedTotal.overflow else {
            throw .resourceLimit(resource: .managedStorageBytes, limit: limits[.managedStorageBytes], requested: nil)
        }
        if let accounting {
            let scoped = activeScope != nil
            let first = try registryGrowth(value: UInt64.self, count: reservations.count,
                                           capacity: reservationCapacity, enabled: !scoped)
            let second = try registryGrowth(value: LogicKernelExternalReservation.self,
                count: scoped ? scopedReservations.count : externalReservations.count,
                capacity: scoped ? scopedCapacity : externalCapacity)
            let copyWork = try registryWork(first, second)
            let work = try checkedCharge(.workUnits, amount: copyWork)
            // Pending leases precede temporary tables. A failure drops the tables
            // explicitly before their pending leases can refund live bytes.
            let payload = try accounting.reserveStorage(byteCount: byteCount)
            try checkpoint()
            let firstLease: (any LogicKernelStorageRetaining)?
            if let first {
                firstLease = try accounting.reserveStorage(byteCount: first.bytes)
                try checkpoint()
            } else { firstLease = nil }
            let secondLease: (any LogicKernelStorageRetaining)?
            if let second {
                secondLease = try accounting.reserveStorage(byteCount: second.bytes)
                try checkpoint()
            } else { secondLease = nil }
            try accounting.charge(.workUnits, amount: copyWork)
            try checkpoint()
            let entry = LogicKernelExternalReservation(byteCount: byteCount, lease: payload)
            var firstTable: [UInt64: UInt64]?
            var secondTable: [UInt64: LogicKernelExternalReservation]?
            do throws(LogicKernelError) {
                if let first {
                    firstTable = try copyRegistry(reservations, capacity: first.capacity,
                        identifier: identifier.partialValue, value: byteCount)
                }
                if let second {
                    secondTable = try copyRegistry(scoped ? scopedReservations : externalReservations,
                        capacity: second.capacity, identifier: identifier.partialValue, value: entry)
                }
            } catch {
                firstTable = nil
                secondTable = nil
                withExtendedLifetime(firstLease) {}
                withExtendedLifetime(secondLease) {}
                withExtendedLifetime(entry) {}
                throw error
            }
            // No fallible action follows: all old/new payloads are still admitted.
            if scoped {
                if let secondTable {
                    scopedReservations = secondTable
                    scopedBacking = secondLease
                    scopedCapacity = second!.capacity
                } else { scopedReservations[identifier.partialValue] = entry }
                scopedBytes = scopedTotal.partialValue
            } else {
                if let firstTable {
                    reservations = firstTable
                    reservationBacking = firstLease
                    reservationCapacity = first!.capacity
                } else { reservations[identifier.partialValue] = byteCount }
                if let secondTable {
                    externalReservations = secondTable
                    externalBacking = secondLease
                    externalCapacity = second!.capacity
                } else { externalReservations[identifier.partialValue] = entry }
            }
            counters[.workUnits] = work
        } else {
            // Preserve the original invocation-only registry and counter behavior.
            reservations[identifier.partialValue] = byteCount
        }
        counters[.storageReservations] = receiptCount
        counters[.managedStorageBytes] = storage
        counters[.allocationBytes] = allocations
        peakStorage = max(peakStorage, storage)
        nextReservation = identifier.partialValue
        return LogicStorageReservation(
            owner: reservationOwner, identifier: nextReservation, byteCount: byteCount
        )
    }

    public mutating func releaseStorage(_ reservation: consuming LogicStorageReservation)
        throws(LogicKernelError) {
        guard reservation.owner === reservationOwner else {
            throw .invalidInput("Storage reservation belongs to a different context")
        }
        if scopedReservations[reservation.identifier]?.byteCount == reservation.byteCount {
            scopedReservations.removeValue(forKey: reservation.identifier)
            scopedBytes -= reservation.byteCount
            if scopedReservations.isEmpty {
                scopedReservations = [:]
                scopedBacking = nil
                scopedCapacity = 0
            }
        } else {
            guard reservations[reservation.identifier] == reservation.byteCount else {
                throw .invalidInput("Storage reservation belongs to a different context")
            }
            reservations.removeValue(forKey: reservation.identifier)
            externalReservations.removeValue(forKey: reservation.identifier)
            if accounting != nil { clearEmptyRegistries() }
        }
        counters[.managedStorageBytes, default: 0] -= reservation.byteCount
    }

    /// Controlled codecs require a shared accountant; no uncontrolled fallback exists.
    public mutating func beginRetentionScope() throws(LogicKernelError) -> LogicKernelRetentionScope {
        guard accounting != nil else { throw .invalidInput("Controlled publication requires external accounting") }
        guard activeScope == nil else { throw .invalidInput("A retention scope is already active") }
        // Stack token fields and the active-scope bookkeeping have an explicit logical offer.
        let metadataBytes = UInt64(MemoryLayout<LogicReservationOwner>.stride + 2 * MemoryLayout<UInt64>.stride)
        let metadata = try reserveStorage(byteCount: metadataBytes)
        activeScope = metadata.identifier
        let scope = LogicKernelRetentionScope(owner: reservationOwner, identifier: metadata.identifier,
                                             metadataReservation: metadata.identifier)
        do throws(LogicKernelError) {
            _ = try reserveStorage(byteCount: LogicKernelRetention.metadataBytes)
            return scope
        } catch {
            try discardRetentionScope(scope)
            throw error
        }
    }

    public mutating func finishRetentionScope(_ scope: borrowing LogicKernelRetentionScope)
        throws(LogicKernelError) -> LogicKernelRetention {
        try validate(scope)
        try checkpoint()
        return transferRetentionScope(scope)
    }

    /// Preserve source-derived diagnostics with only storage admitted before failure.
    public mutating func retainFailureScope(_ scope: borrowing LogicKernelRetentionScope)
        throws(LogicKernelError) -> LogicKernelRetention {
        try validate(scope)
        return transferRetentionScope(scope)
    }

    private mutating func transferRetentionScope(_ scope: borrowing LogicKernelRetentionScope) -> LogicKernelRetention {
        // Both dictionary and immutable anchor fields were admitted by beginRetentionScope.
        let entries = scopedReservations
        let backing = scopedBacking
        scopedReservations = [:]
        scopedBacking = nil
        scopedCapacity = 0
        scopedBytes = 0
        activeScope = nil
        releaseScopeMetadata(scope)
        return LogicKernelRetention(entries: entries, backing: backing)
    }

    /// Failure cleanup cannot observe cancellation and never refunds cumulative work.
    public mutating func discardRetentionScope(_ scope: borrowing LogicKernelRetentionScope)
        throws(LogicKernelError) {
        try validate(scope)
        counters[.managedStorageBytes, default: 0] -= scopedBytes
        scopedBytes = 0
        scopedReservations = [:]
        scopedBacking = nil
        scopedCapacity = 0
        activeScope = nil
        releaseScopeMetadata(scope)
    }

    private borrowing func validate(_ scope: borrowing LogicKernelRetentionScope) throws(LogicKernelError) {
        guard scope.owner === reservationOwner, activeScope == scope.identifier else {
            throw .invalidInput("Retention scope is inactive or belongs to a different context")
        }
    }

    private mutating func releaseScopeMetadata(_ scope: borrowing LogicKernelRetentionScope) {
        // beginRetentionScope establishes this exact live entry before publishing the token.
        let bytes = reservations.removeValue(forKey: scope.metadataReservation)!
        externalReservations.removeValue(forKey: scope.metadataReservation)
        clearEmptyRegistries()
        counters[.managedStorageBytes, default: 0] -= bytes
    }

    private mutating func clearEmptyRegistries() {
        if reservations.isEmpty {
            reservations = [:]
            reservationBacking = nil
            reservationCapacity = 0
        }
        if externalReservations.isEmpty {
            externalReservations = [:]
            externalBacking = nil
            externalCapacity = 0
        }
    }

    private struct RegistryGrowth {
        let capacity: Int
        let bytes: UInt64
        let work: UInt64
    }

    private borrowing func registryGrowth<Value>(value: Value.Type, count: Int,
        capacity: Int, enabled: Bool = true) throws(LogicKernelError) -> RegistryGrowth? {
        guard enabled, count >= capacity else { return nil }
        let required = try registryAdd(count, 1)
        var buckets = 2
        // Swift 6.4.0 _HashTable uses power-of-two buckets and a 3/4 load factor.
        while buckets / 2 + buckets / 4 < required {
            buckets = try registryMultiply(buckets, 2)
        }
        let words = try registryAdd(buckets, UInt.bitWidth - 1) / UInt.bitWidth
        // HeapObject header, then the exact __RawDictionaryStorage declared fields.
        let fields = MemoryLayout<(Int, Int, Int8, Int8, Int16, Int32, Int, UInt, UInt)>.stride
        var bytes = try registryAdd(2 * MemoryLayout<UInt>.stride, fields)
        bytes = try registryAligned(bytes, to: MemoryLayout<UInt>.alignment)
        bytes = try registryAdd(bytes, try registryMultiply(words, MemoryLayout<UInt>.stride))
        bytes = try registryAligned(bytes, to: MemoryLayout<UInt64>.alignment)
        bytes = try registryAdd(bytes, try registryMultiply(buckets, MemoryLayout<UInt64>.stride))
        bytes = try registryAligned(bytes, to: MemoryLayout<Value>.alignment)
        bytes = try registryAdd(bytes, try registryMultiply(buckets, MemoryLayout<Value>.stride))
        let work = try registryAdd(try registryAdd(buckets, words), count)
        return RegistryGrowth(capacity: buckets / 2 + buckets / 4,
                              bytes: UInt64(bytes), work: UInt64(work))
    }

    private borrowing func registryWork(_ first: RegistryGrowth?, _ second: RegistryGrowth?)
        throws(LogicKernelError) -> UInt64 {
        // Each insertion also initializes one actual entry in its enabled table.
        let base: UInt64 = activeScope == nil ? 2 : 1
        let firstSum = base.addingReportingOverflow(first?.work ?? 0)
        let total = firstSum.partialValue.addingReportingOverflow(second?.work ?? 0)
        guard !firstSum.overflow, !total.overflow else {
            throw .resourceLimit(resource: .workUnits, limit: limits[.workUnits], requested: nil)
        }
        return total.partialValue
    }

    private borrowing func copyRegistry<Value>(_ source: [UInt64: Value], capacity: Int,
        identifier: UInt64, value: Value) throws(LogicKernelError) -> [UInt64: Value] {
        var result = [UInt64: Value](minimumCapacity: capacity)
        for (key, element) in source {
            try checkpoint()
            result[key] = element
        }
        try checkpoint()
        result[identifier] = value
        return result
    }

    private borrowing func registryAdd(_ a: Int, _ b: Int) throws(LogicKernelError) -> Int {
        let result = a.addingReportingOverflow(b)
        guard !result.overflow else { throw registryOverflow() }
        return result.partialValue
    }

    private borrowing func registryMultiply(_ a: Int, _ b: Int) throws(LogicKernelError) -> Int {
        let result = a.multipliedReportingOverflow(by: b)
        guard !result.overflow else { throw registryOverflow() }
        return result.partialValue
    }

    private borrowing func registryAligned(_ bytes: Int, to alignment: Int) throws(LogicKernelError) -> Int {
        let remainder = bytes % alignment
        return remainder == 0 ? bytes : try registryAdd(bytes, alignment - remainder)
    }

    private borrowing func registryOverflow() -> LogicKernelError {
        .resourceLimit(resource: .managedStorageBytes, limit: limits[.managedStorageBytes], requested: nil)
    }

    /// Merge a trusted, pre-admitted source phase exactly once without charging it twice.
    /// This operation must also run when that phase fails or is cancelled.
    public mutating func importAccountedPhase(peakStorageBytes: UInt64, allocationBytes: UInt64,
        storageReservations: UInt64, workUnits: UInt64, expectedAccounting: any LogicKernelAccounting)
        throws(LogicKernelError) {
        try requireAccounting(expected: expectedAccounting)
        guard allocationBytes >= peakStorageBytes, peakStorageBytes == 0 || storageReservations > 0 else {
            throw .invalidInput("Invalid already-accounted phase storage counters")
        }
        let storage = try checkedCharge(.managedStorageBytes, amount: peakStorageBytes)
        let allocations = try checkedCharge(.allocationBytes, amount: allocationBytes)
        let reservations = try checkedCharge(.storageReservations, amount: storageReservations)
        let work = try checkedCharge(.workUnits, amount: workUnits)
        counters[.managedStorageBytes] = storage
        counters[.allocationBytes] = allocations
        counters[.storageReservations] = reservations
        counters[.workUnits] = work
        peakStorage = max(peakStorage, storage)
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
