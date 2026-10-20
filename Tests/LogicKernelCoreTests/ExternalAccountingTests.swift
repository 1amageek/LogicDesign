import Testing
import Synchronization
import LogicKernelCore

@Suite(.timeLimit(.minutes(1)))
struct ExternalAccountingTests {
    private struct Control: LogicRunControlling {
        func checkpoint() throws(LogicKernelError) {}
    }
    @available(macOS 15.0, *)
    private final class Accountant: LogicKernelAccounting {
        struct State {
            var live: UInt64 = 0
            var peak: UInt64 = 0
            var allocated: UInt64 = 0
            var work: UInt64 = 0
            var refuse = false
            var refuseWork = false
            var remainingReservations: Int?
            var released: [UInt64] = []
        }
        let state = Mutex(State())
        let cancel: (@Sendable () -> Void)?
        init(cancel: (@Sendable () -> Void)? = nil) { self.cancel = cancel }
        func observeBitWidth(_ width: UInt64) throws(LogicKernelError) {
            if state.withLock({ $0.refuse }) { throw .externalAccountingFailure }
            cancel?()
        }
        func charge(_ resource: LogicResource, amount: UInt64) throws(LogicKernelError) {
            let refused = state.withLock { value in
                if value.refuse || value.refuseWork { return true }
                value.work += amount
                return false
            }
            if refused { throw .externalAccountingFailure }
            cancel?()
        }
        func reserveStorage(byteCount: UInt64) throws(LogicKernelError) -> any LogicKernelStorageRetaining {
            let refused = state.withLock { value in
                if value.refuse { return true }
                if let remaining = value.remainingReservations {
                    if remaining == 0 { return true }
                    value.remainingReservations = remaining - 1
                }
                value.live += byteCount; value.allocated += byteCount
                value.peak = max(value.peak, value.live)
                return false
            }
            if refused { throw .externalAccountingFailure }
            let result = Lease(owner: self, bytes: byteCount)
            cancel?()
            return result
        }
        private final class Lease: LogicKernelStorageRetaining {
            let owner: Accountant; let bytes: UInt64
            init(owner: Accountant, bytes: UInt64) { self.owner = owner; self.bytes = bytes }
            deinit { owner.state.withLock { $0.live -= bytes; $0.released.append(bytes) } }
        }
    }
    private func limits() throws -> LogicKernelLimits {
        try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, 1_000_000) }))
    }
    @Test func refusalPrecedesEveryLocalCommitAndOwnerMustMatch() throws {
        guard #available(macOS 15.0, *) else { Issue.record("Controlled contract verification requires macOS 15.0"); return }
        let owner = Accountant(); let other = Accountant()
        var context = LogicKernelContext(limits: try limits(), control: Control(), accounting: owner)
        try context.requireAccounting(expected: owner)
        #expect(throws: LogicKernelError.self) { try context.requireAccounting(expected: other) }
        owner.state.withLock { $0.refuse = true }
        let before = context.usage
        #expect(throws: LogicKernelError.externalAccountingFailure) { try context.charge(.workUnits) }
        #expect(throws: LogicKernelError.externalAccountingFailure) { try context.observeBitWidth(8) }
        #expect(throws: LogicKernelError.externalAccountingFailure) { _ = try context.reserveStorage(byteCount: 12) }
        #expect(context.usage == before)
        #expect(owner.state.withLock { $0.live } == 0)
    }
    @Test func postAdmissionCancellationRefundsLeaseWithoutResettingAllocation() throws {
        guard #available(macOS 15.0, *) else { Issue.record("Controlled contract verification requires macOS 15.0"); return }
        // Use one reference owner for the cancellation state on all targets.
        final class Flag: Sendable { let value = Mutex(false) }
        let flag = Flag()
        struct SharedControl: LogicRunControlling {
            let flag: Flag
            func checkpoint() throws(LogicKernelError) { if flag.value.withLock({ $0 }) { throw .cancelled } }
        }
        let owner = Accountant(cancel: { flag.value.withLock { $0 = true } })
        var context = LogicKernelContext(limits: try limits(), control: SharedControl(flag: flag), accounting: owner)
        let before = context.usage
        #expect(throws: LogicKernelError.cancelled) { _ = try context.reserveStorage(byteCount: 23) }
        #expect(context.usage == before)
        #expect(owner.state.withLock { $0.live } == 0)
        #expect(owner.state.withLock { $0.allocated } >= 23)
    }
    @Test func failureScopeRefundsStorageButNotCumulativeWorkAndTokensExpire() throws {
        guard #available(macOS 15.0, *) else { Issue.record("Controlled contract verification requires macOS 15.0"); return }
        let owner = Accountant()
        var context = LogicKernelContext(limits: try limits(), control: Control(), accounting: owner)
        let scope = try context.beginRetentionScope()
        _ = try context.reserveStorage(byteCount: 100)
        let administrativeWork = context.usage[.workUnits]
        try context.charge(.workUnits, amount: 7)
        let allocated = context.usage[.allocationBytes]
        try context.discardRetentionScope(scope)
        #expect(context.usage[.managedStorageBytes] == 0)
        #expect(context.usage[.allocationBytes] == allocated)
        #expect(context.usage[.workUnits] == administrativeWork + 7)
        #expect(owner.state.withLock { $0.live } == 0)
        #expect(throws: LogicKernelError.self) { try context.discardRetentionScope(scope) }
    }
    @Test func successfulAnchorCoversCopiesAfterContextDestruction() throws {
        guard #available(macOS 15.0, *) else { Issue.record("Controlled contract verification requires macOS 15.0"); return }
        let owner = Accountant()
        func result() throws -> LogicKernelRetention {
            var context = LogicKernelContext(limits: try limits(), control: Control(), accounting: owner)
            let scope = try context.beginRetentionScope()
            #expect(throws: LogicKernelError.self) { _ = try context.beginRetentionScope() }
            _ = try context.reserveStorage(byteCount: 100)
            let result = try context.finishRetentionScope(scope)
            #expect(throws: LogicKernelError.self) { _ = try context.finishRetentionScope(scope) }
            return result
        }
        var first: LogicKernelRetention? = try result()
        var second = first
        #expect(owner.state.withLock { $0.live } > 0)
        first = nil
        withExtendedLifetime(second) { #expect(owner.state.withLock { $0.live } > 0) }
        second = nil
        #expect(owner.state.withLock { $0.live } == 0)
    }
    @Test func missingAccountantAndForeignScopeAreRefused() throws {
        guard #available(macOS 15.0, *) else { Issue.record("Controlled contract verification requires macOS 15.0"); return }
        var legacy = LogicKernelContext(limits: try limits(), control: Control())
        #expect(throws: LogicKernelError.self) { _ = try legacy.beginRetentionScope() }
        let owner = Accountant()
        var first = LogicKernelContext(limits: try limits(), control: Control(), accounting: owner)
        var second = LogicKernelContext(limits: try limits(), control: Control(), accounting: owner)
        let scope = try first.beginRetentionScope()
        #expect(throws: LogicKernelError.self) { try second.discardRetentionScope(scope) }
        try first.discardRetentionScope(scope)
    }
    @Test func accountedPhaseImportsLocallyOnceWithoutCallbackOrCancellation() throws {
        guard #available(macOS 15.0, *) else { Issue.record("Controlled contract verification requires macOS 15.0"); return }
        let owner = Accountant(); let cancellation = LogicCancellationSource()
        var context = LogicKernelContext(limits: try limits(), control: cancellation, accounting: owner)
        cancellation.cancel()
        try context.importAccountedPhase(peakStorageBytes: 20, allocationBytes: 35,
            storageReservations: 2, workUnits: 7, expectedAccounting: owner)
        #expect(context.usage[.managedStorageBytes] == 20)
        #expect(context.usage[.allocationBytes] == 35)
        #expect(context.usage[.storageReservations] == 2)
        #expect(context.usage[.workUnits] == 7)
        #expect(owner.state.withLock { $0.work == 0 && $0.live == 0 && $0.allocated == 0 })
        let before = context.usage
        #expect(throws: LogicKernelError.self) {
            try context.importAccountedPhase(peakStorageBytes: 21, allocationBytes: 20,
                storageReservations: 2, workUnits: 7, expectedAccounting: owner)
        }
        #expect(throws: LogicKernelError.self) {
            try context.importAccountedPhase(peakStorageBytes: 1, allocationBytes: 1,
                storageReservations: 0, workUnits: 7, expectedAccounting: owner)
        }
        #expect(throws: LogicKernelError.self) {
            try context.importAccountedPhase(peakStorageBytes: 0, allocationBytes: .max,
                storageReservations: 0, workUnits: 7, expectedAccounting: owner)
        }
        #expect(throws: LogicKernelError.self) {
            try context.importAccountedPhase(peakStorageBytes: 1, allocationBytes: 1,
                storageReservations: 1, workUnits: 1, expectedAccounting: Accountant())
        }
        #expect(context.usage == before)
    }
    @Test func checkpointGetterObservesTheOriginalAAndIndependentB() throws {
        guard #available(macOS 15.0, *) else { Issue.record("Controlled contract verification requires macOS 15.0"); return }
        let a = LogicCancellationSource(); let b = LogicCancellationSource()
        struct Both: LogicRunControlling {
            let a: any LogicRunControlling; let b: LogicCancellationSource
            func checkpoint() throws(LogicKernelError) { try a.checkpoint(); try b.checkpoint() }
        }
        let owner = Accountant()
        let context = LogicKernelContext(limits: try limits(), control: a, accounting: owner)
        let bridge = Both(a: context.checkpointControl, b: b)
        try bridge.checkpoint()
        a.cancel()
        #expect(throws: LogicKernelError.cancelled) { try bridge.checkpoint() }
        let fresh = LogicCancellationSource()
        let independent = Both(a: fresh, b: b)
        b.cancel()
        #expect(throws: LogicKernelError.cancelled) { try independent.checkpoint() }
    }

    @Test func failureTransferNeedsNoFreshAdmissionOrCancellationCheck() throws {
        guard #available(macOS 15.0, *) else { Issue.record("Controlled contract verification requires macOS 15.0"); return }
        let owner = Accountant(); let control = LogicCancellationSource()
        var context = LogicKernelContext(limits: try limits(), control: control, accounting: owner)
        let scope = try context.beginRetentionScope()
        _ = try context.reserveStorage(byteCount: 71)
        owner.state.withLock { $0.refuse = true }
        control.cancel()
        var retained: LogicKernelRetention? = try context.retainFailureScope(scope)
        #expect(owner.state.withLock { $0.live } > 0)
        withExtendedLifetime(retained) {}
        retained = nil
        #expect(owner.state.withLock { $0.live } == 0)
        #expect(throws: LogicKernelError.self) { _ = try context.retainFailureScope(scope) }
    }

    @Test func anchorMetadataRefusalRollsBackThePartiallyOpenedScope() throws {
        guard #available(macOS 15.0, *) else { Issue.record("Controlled contract verification requires macOS 15.0"); return }
        let owner = Accountant()
        // The first metadata receipt admits payload plus its two registry tables.
        // Refuse the next receipt, after the scope has genuinely opened.
        owner.state.withLock { $0.remainingReservations = 3 }
        var context = LogicKernelContext(limits: try limits(), control: Control(), accounting: owner)
        #expect(throws: LogicKernelError.externalAccountingFailure) { _ = try context.beginRetentionScope() }
        #expect(context.usage[.managedStorageBytes] == 0)
        #expect(owner.state.withLock { $0.live } == 0)
        #expect(context.usage[.allocationBytes] > 0)
        owner.state.withLock { $0.remainingReservations = nil }
        let retry = try context.beginRetentionScope()
        try context.discardRetentionScope(retry)
        #expect(owner.state.withLock { $0.live } == 0)
    }

    @Test func zeroByteReceiptStillAdmitsBothConcreteRegistryBackings() throws {
        guard #available(macOS 15.0, *) else { Issue.record("Controlled contract verification requires macOS 15.0"); return }
        let owner = Accountant()
        var context = LogicKernelContext(limits: try limits(), control: Control(), accounting: owner)
        let reservation = try context.reserveStorage(byteCount: 0)
        // A nonempty Swift dictionary has at least two key/value buckets. These
        // independent lower bounds deliberately omit headers and occupancy words.
        let reservationBuckets = 2 * MemoryLayout<(UInt64, UInt64)>.stride
        let externalEntry = MemoryLayout<(UInt64, any LogicKernelStorageRetaining)>.stride
        let externalBuckets = 2 * (MemoryLayout<UInt64>.stride + externalEntry)
        #expect(owner.state.withLock { $0.live } >= UInt64(reservationBuckets + externalBuckets))
        #expect(context.usage[.managedStorageBytes] == 0)
        try context.releaseStorage(reservation)
        #expect(owner.state.withLock { $0.live } == 0)
    }

    @Test func registryGrowthRetainsOldAndNewBackingUntilCommit() throws {
        guard #available(macOS 15.0, *) else { Issue.record("Controlled contract verification requires macOS 15.0"); return }
        let owner = Accountant()
        var context = LogicKernelContext(limits: try limits(), control: Control(), accounting: owner)
        let first = try context.reserveStorage(byteCount: 0)
        let oldLive = owner.state.withLock { $0.live }
        let second = try context.reserveStorage(byteCount: 0)
        let newLive = owner.state.withLock { $0.live }
        #expect(owner.state.withLock { $0.peak } >= oldLive + newLive)
        #expect(newLive > oldLive)
        let allocated = owner.state.withLock { $0.allocated }
        let third = try context.reserveStorage(byteCount: 0)
        // Three-quarter load gives three entries in the existing four buckets.
        #expect(owner.state.withLock { $0.allocated } == allocated)
        try context.releaseStorage(first)
        #expect(owner.state.withLock { $0.live } == newLive)
        try context.releaseStorage(second)
        #expect(owner.state.withLock { $0.live } == newLive)
        try context.releaseStorage(third)
        #expect(owner.state.withLock { $0.live } == 0)
        for _ in 0..<16 {
            let receipt = try context.reserveStorage(byteCount: 0)
            #expect(owner.state.withLock { $0.live } == oldLive)
            try context.releaseStorage(receipt)
            #expect(owner.state.withLock { $0.live } == 0)
        }
    }

    @Test(arguments: [1, 2, 3])
    func partialRegistryAdmissionAndWorkRefusalPreserveLocalUsage(successfulAdmissions: Int) throws {
        guard #available(macOS 15.0, *) else { Issue.record("Controlled contract verification requires macOS 15.0"); return }
        let owner = Accountant()
        owner.state.withLock {
            $0.remainingReservations = successfulAdmissions
            $0.refuseWork = successfulAdmissions == 3
        }
        var context = LogicKernelContext(limits: try limits(), control: Control(), accounting: owner)
        let before = context.usage
        #expect(throws: LogicKernelError.externalAccountingFailure) { _ = try context.reserveStorage(byteCount: 19) }
        #expect(context.usage == before)
        #expect(owner.state.withLock { $0.live } == 0)
        #expect(owner.state.withLock { $0.allocated } >= 19)
        owner.state.withLock { $0.remainingReservations = nil; $0.refuseWork = false }
        let retry = try context.reserveStorage(byteCount: 19)
        try context.releaseStorage(retry)
        #expect(owner.state.withLock { $0.live } == 0)
    }

    @Test func administrativeWorkLimitRefusesBeforeAnyExternalAdmission() throws {
        guard #available(macOS 15.0, *) else { Issue.record("Controlled contract verification requires macOS 15.0"); return }
        let owner = Accountant()
        let limits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
            LogicResource.allCases.map { ($0, $0 == .workUnits ? UInt64(1) : UInt64(1_000_000)) }))
        var context = LogicKernelContext(limits: limits, control: Control(), accounting: owner)
        let before = context.usage
        #expect(throws: LogicKernelError.self) { _ = try context.reserveStorage(byteCount: 0) }
        #expect(context.usage == before)
        #expect(owner.state.withLock { $0.allocated == 0 && $0.live == 0 && $0.work == 0 })
        // Without an accountant there is no new administrative-work path.
        var legacy = LogicKernelContext(limits: limits, control: Control())
        let receipt = try legacy.reserveStorage(byteCount: 0)
        #expect(legacy.usage[.workUnits] == 0)
        try legacy.releaseStorage(receipt)
    }

    @Test func cancellationDuringGrowthRetainsOnlyTheOriginalTables() throws {
        guard #available(macOS 15.0, *) else { Issue.record("Controlled contract verification requires macOS 15.0"); return }
        final class Flag: Sendable { let value = Mutex(false); let callbacks = Mutex(0) }
        struct SharedControl: LogicRunControlling {
            let flag: Flag
            func checkpoint() throws(LogicKernelError) { if flag.value.withLock({ $0 }) { throw .cancelled } }
        }
        let flag = Flag()
        let owner = Accountant(cancel: {
            let callback = flag.callbacks.withLock { $0 += 1; return $0 }
            if callback == 5 { flag.value.withLock { $0 = true } }
        })
        var context = LogicKernelContext(limits: try limits(), control: SharedControl(flag: flag), accounting: owner)
        let first = try context.reserveStorage(byteCount: 17)
        let before = context.usage
        let live = owner.state.withLock { $0.live }
        let allocated = owner.state.withLock { $0.allocated }
        #expect(throws: LogicKernelError.cancelled) { _ = try context.reserveStorage(byteCount: 29) }
        #expect(context.usage == before)
        #expect(owner.state.withLock { $0.live } == live)
        #expect(owner.state.withLock { $0.allocated } == allocated + 29)
        try context.releaseStorage(first)
        #expect(owner.state.withLock { $0.live } == 0)
    }

    @Test func pinnedDestructionOrderKeepsBackingUntilPayloadsAreReleased() throws {
        guard #available(macOS 15.0, *) else { Issue.record("Controlled contract verification requires macOS 15.0"); return }
        let owner = Accountant()
        do {
            var context = LogicKernelContext(limits: try limits(), control: Control(), accounting: owner)
            _ = try context.reserveStorage(byteCount: 71)
        }
        let contextEvents = owner.state.withLock { $0.released }
        #expect(contextEvents.count == 3)
        #expect(contextEvents.first == 71)
        #expect(owner.state.withLock { $0.live } == 0)

        var context = LogicKernelContext(limits: try limits(), control: Control(), accounting: owner)
        let scope = try context.beginRetentionScope()
        _ = try context.reserveStorage(byteCount: 71)
        var first: LogicKernelRetention? = try context.finishRetentionScope(scope)
        var second = first
        first = nil
        let backingBytes = owner.state.withLock { $0.live } - 71
            - UInt64(2 * MemoryLayout<UInt>.stride + MemoryLayout<[UInt64: UInt64]>.stride
                     + MemoryLayout<(any LogicKernelStorageRetaining)?>.stride)
        owner.state.withLock { $0.released = [] }
        withExtendedLifetime(second) { #expect(owner.state.withLock { $0.live } > 0) }
        second = nil
        let anchorEvents = owner.state.withLock { $0.released }
        #expect(anchorEvents.count == 3)
        #expect(anchorEvents.last == backingBytes)
        #expect(anchorEvents.dropLast().contains(71))
        #expect(owner.state.withLock { $0.live } == 0)
    }

}
