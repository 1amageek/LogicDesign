import Testing
import LogicKernelCore
import CircuiteFoundation

@Suite(.timeLimit(.minutes(1)))
struct ExecutionControlTests {
    private struct Control: LogicRunControlling {
        var failure: LogicKernelError?
        func checkpoint() throws(LogicKernelError) {
            if let failure { throw failure }
        }
    }

    private func limits(_ overrides: [LogicResource: UInt64] = [:]) throws -> LogicKernelLimits {
        var values = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(100)) })
        for (key, value) in overrides { values[key] = value }
        return try LogicKernelLimits(maximums: values)
    }

    @Test func sourceRangesAreBoundToExactBytes() throws {
        let digest = try ContentDigest(algorithm: .sha256, hexadecimalValue: String(repeating: "0", count: 64))
        let artifact = try ArtifactID(digest: digest, byteCount: 10)
        let range = try LogicKernelSourceRange(artifactID: artifact, byteRange: 2..<10)
        #expect(range.artifactID == artifact)
        #expect(range.byteRange == 2..<10)
        #expect(throws: LogicKernelError.self) {
            try LogicKernelSourceRange(artifactID: artifact, byteRange: 0..<11)
        }
    }

    @Test func invalidLimitsAreRejected() throws {
        #expect(throws: LogicKernelError.self) { try LogicKernelLimits(maximums: [:]) }
        #expect(throws: LogicKernelError.self) { try limits([.workUnits: 0]) }
    }

    @Test func stagesShareOneCumulativeBudget() throws {
        var context = LogicKernelContext(limits: try limits([.workUnits: 5]), control: Control())
        try context.charge(.workUnits, amount: 3)
        try context.charge(.workUnits, amount: 2)
        let before = context.usage
        do {
            try context.charge(.workUnits)
            Issue.record("Expected cumulative resource exhaustion")
        } catch {
            #expect(error == .resourceLimit(resource: .workUnits, limit: 5, requested: 6))
        }
        #expect(context.usage == before)
    }

    @Test func overflowIsRejectedBeforeMutation() throws {
        var context = LogicKernelContext(
            limits: try limits([.searchSteps: .max]), control: Control()
        )
        try context.charge(.searchSteps, amount: .max)
        do {
            try context.charge(.searchSteps)
            Issue.record("Expected overflow failure")
        } catch {
            #expect(error == .resourceLimit(resource: .searchSteps, limit: .max, requested: nil))
        }
        #expect(context.usage[.searchSteps] == .max)
    }

    @Test func storageTracksOverlapAndCumulativeAllocation() throws {
        var context = LogicKernelContext(limits: try limits(), control: Control())
        let first = try context.reserveStorage(byteCount: 40)
        let second = try context.reserveStorage(byteCount: 60)
        #expect(context.usage[.managedStorageBytes] == 100)
        #expect(context.usage.peakManagedStorageBytes == 100)
        let before = context.usage
        do {
            _ = try context.reserveStorage(byteCount: 1)
            Issue.record("Expected storage limit")
        } catch {
            #expect(error == .resourceLimit(resource: .managedStorageBytes, limit: 100, requested: 101))
        }
        #expect(context.usage == before)
        try context.releaseStorage(first)
        try context.releaseStorage(second)
        #expect(context.usage[.managedStorageBytes] == 0)
        #expect(context.usage[.allocationBytes] == 100)
        do {
            _ = try context.reserveStorage(byteCount: 1)
            Issue.record("Expected cumulative allocation limit")
        } catch {
            #expect(error == .resourceLimit(resource: .allocationBytes, limit: 100, requested: 101))
        }
        #expect(context.usage[.managedStorageBytes] == 0)
    }

    @Test func zeroByteReservationsStillHaveABoundedRegistry() throws {
        var context = LogicKernelContext(limits: try limits([.storageReservations: 1]), control: Control())
        let receipt = try context.reserveStorage(byteCount: 0)
        let before = context.usage
        do {
            _ = try context.reserveStorage(byteCount: 0)
            Issue.record("Expected reservation-count exhaustion")
        } catch {
            #expect(error == .resourceLimit(resource: .storageReservations, limit: 1, requested: 2))
        }
        #expect(context.usage == before)
        try context.releaseStorage(receipt)
        #expect(context.usage[.storageReservations] == 1)
    }

    @Test func foreignReservationDoesNotReleaseStorage() throws {
        var first = LogicKernelContext(limits: try limits(), control: Control())
        var second = LogicKernelContext(limits: try limits(), control: Control())
        let reservation = try first.reserveStorage(byteCount: 10)
        do {
            try second.releaseStorage(reservation)
            Issue.record("Expected reservation ownership failure")
        } catch {
            #expect(error == .invalidInput("Storage reservation belongs to a different context"))
        }
        #expect(first.usage[.managedStorageBytes] == 10)
        #expect(second.usage[.managedStorageBytes] == 0)
    }

    @Test func widthIsMaximumRatherThanCumulative() throws {
        var context = LogicKernelContext(limits: try limits(), control: Control())
        try context.observeBitWidth(65)
        try context.observeBitWidth(32)
        #expect(context.usage[.bitWidth] == 65)
        #expect(throws: LogicKernelError.self) { try context.observeBitWidth(0) }
        #expect(context.usage[.bitWidth] == 65)
    }

    @Test func deadlineAndCancellationRemainDistinct() throws {
        var context = LogicKernelContext(limits: try limits(), control: Control(failure: .deadlineExceeded))
        do {
            try context.charge(.nodes)
            Issue.record("Expected deadline")
        } catch { #expect(error == .deadlineExceeded) }
        #expect(context.usage[.nodes] == 0)
        guard #available(macOS 15.0, *) else {
            Issue.record("Cancellation requires macOS 15 or newer")
            return
        }
        let cancellation = LogicCancellationSource()
        cancellation.cancel()
        var cancelled = LogicKernelContext(limits: try limits(), control: cancellation)
        do {
            try cancelled.charge(.nodes)
            Issue.record("Expected cancellation")
        } catch { #expect(error == .cancelled) }
        #expect(cancelled.usage[.nodes] == 0)
    }

    @Test func concurrentCancellationIsMonotonic() async {
        guard #available(macOS 15.0, *) else {
            Issue.record("Cancellation requires macOS 15 or newer")
            return
        }
        let source = LogicCancellationSource()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    source.cancel()
                    #expect(source.isCancelled)
                    do {
                        try source.checkpoint()
                        Issue.record("Expected cancellation")
                    } catch let error as LogicKernelError {
                        #expect(error == .cancelled)
                    } catch { Issue.record(error) }
                }
            }
        }
        #expect(source.isCancelled)
    }
}
