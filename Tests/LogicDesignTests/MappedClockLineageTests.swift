import Foundation
import Synchronization
import CircuiteFoundation
import Testing
import LogicIR
import LogicKernelCore
import LogicKernelProbeSupport
import LogicDesignSerialization

@Suite(.timeLimit(.minutes(1)))
struct MappedClockLineageTests {
    private struct Control: LogicRunControlling { func checkpoint() throws(LogicKernelError) {} }
    private func context(work: UInt64 = 10_000_000, storage: UInt64 = 10_000_000) throws -> LogicKernelContext {
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(10_000_000)) })
        limits[.workUnits] = work; limits[.managedStorageBytes] = storage
        return .init(limits: try .init(maximums: limits), control: Control())
    }

    @available(macOS 26.0, *)
    @Test func actualUnaryBranchesAndLegacyOpaqueProfiles() throws {
        try exerciseMappedClockLineageContract()
    }

    @available(macOS 26.0, *)
    @Test func decodeRederivesClockLineageFromActualConnections() throws {
        var run = try context()
        let library = try clockLineageProbeLibrary(context: &run)
        let codec = MappedGateDesignCodec()
        for scenario in [0, 1, 2, 3, 8, 9, 10, 12] {
            let original = try clockLineageProbeDesign(scenario: scenario, library: library, context: &run)
            let bytes = try codec.encode(original)
            #expect(!String(decoding: bytes, as: UTF8.self).contains("lineage"))
            let decoded = try codec.decode(bytes, library: library, context: &run)
            let expected = original.withStateClocks { clocks in clocks.indices.map { clocks[$0] } }
            #expect(decoded.withStateClocks { clocks in clocks.indices.map { clocks[$0] } } == expected)
        }
    }

    @available(macOS 26.0, *)
    @Test func cumulativeWorkAndTemporaryStorageFailureRemainAtomic() throws {
        var baseline = try context()
        let library = try clockLineageProbeLibrary(context: &baseline)
        let before = baseline.usage[.workUnits]
        _ = try clockLineageProbeDesign(scenario: 0, library: library, context: &baseline)
        let required = baseline.usage[.workUnits] - before
        var limited = try context(work: required - 1)
        do throws(LogicKernelError) {
            _ = try clockLineageProbeDesign(scenario: 0, library: library, context: &limited)
            Issue.record("Clock derivation ignored cumulative work")
        } catch .resourceLimit(let resource, _, _) { #expect(resource == .workUnits) }
        var successful = try context(work: required)
        _ = try clockLineageProbeDesign(scenario: 0, library: library, context: &successful)
        #expect(successful.usage[.workUnits] == required)
        #expect(successful.usage.peakManagedStorageBytes > successful.usage[.managedStorageBytes])
        var storageLimited = try context(storage: successful.usage.peakManagedStorageBytes - 1)
        #expect(throws: LogicKernelError.self) {
            try clockLineageProbeDesign(scenario: 0, library: library, context: &storageLimited)
        }
        #expect(storageLimited.usage[.managedStorageBytes] == successful.usage[.managedStorageBytes])
    }
    @available(macOS 26.0, *)
    @Test func longEvenInverterChainUsesConnectivityAndRetainsActualCells() throws {
        var run = try context()
        let library = try clockLineageProbeLibrary(context: &run)
        let depth = 128
        var builder = try MappedGateBuilder(library: library, capacity: .init(nets: depth + 4,
            instances: depth + 2, pinConnections: 3 * (depth + 2), ports: 2, portBits: 4), context: &run)
        func id(_ value: Int) throws -> DesignEntityID { try .init(rawValue: UInt64(value)) }
        for index in 0..<2 { _ = try builder.addNet(.init(id: id(index + 1), driver: .input), context: &run) }
        for index in 0..<(depth + 2) {
            _ = try builder.addNet(.init(id: id(index + 3), driver: .instanceOutput(.init(index), .init(2))), context: &run)
        }
        for index in 0..<depth {
            _ = try builder.addInstance(id: id(1000 + index), cell: .init(1),
                pinNets: [.init(index == 0 ? 0 : index + 1), .init(1), .init(index + 2)], context: &run)
        }
        for index in 0..<2 {
            _ = try builder.addInstance(id: id(2000 + index), cell: .init(4),
                pinNets: [.init(1), .init(index == 0 ? 0 : depth + 1), .init(depth + 2 + index)],
                stateID: id(3000 + index), context: &run)
        }
        try builder.addPort(id: id(4000), direction: .input, nets: [.init(0), .init(1)], context: &run)
        try builder.addPort(id: id(4001), direction: .output, nets: [.init(depth + 2), .init(depth + 3)], context: &run)
        let design = try builder.finish(context: &run)
        #expect(design.instanceCount == depth + 2)
        #expect(design.withStateClocks { clocks in clocks.count == 2 && clocks[0].lineage == clocks[1].lineage })
    }

    @available(macOS 15.0, *)
    private final class ControlledCheckpoint: LogicRunControlling {
        private struct State { var count = 0; let failAt: Int?; let failure: LogicKernelError }
        private let state: Mutex<State>
        init(failAt: Int? = nil, failure: LogicKernelError = .cancelled) {
            state = Mutex(State(failAt: failAt, failure: failure))
        }
        var count: Int { state.withLock { $0.count } }
        func checkpoint() throws(LogicKernelError) {
            let error = state.withLock { state -> LogicKernelError? in
                state.count += 1
                return state.failAt == state.count ? state.failure : nil
            }
            if let error { throw error }
        }
    }

    @available(macOS 26.0, *)
    @Test func lateCancellationAndDeadlinePropagateWithoutPublishing() throws {
        var libraryRun = try context()
        let library = try clockLineageProbeLibrary(context: &libraryRun)
        let limits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
            LogicResource.allCases.map { ($0, UInt64(10_000_000)) }))
        let baselineControl = ControlledCheckpoint()
        var baseline = LogicKernelContext(limits: limits, control: baselineControl)
        _ = try clockLineageProbeDesign(scenario: 0, library: library, context: &baseline)
        for failure in [LogicKernelError.cancelled, .deadlineExceeded] {
            let control = ControlledCheckpoint(failAt: baselineControl.count, failure: failure)
            var run = LogicKernelContext(limits: limits, control: control)
            #expect(throws: failure) { try clockLineageProbeDesign(scenario: 0, library: library, context: &run) }
            #expect(run.usage[.managedStorageBytes] == baseline.usage[.managedStorageBytes])
        }
    }

}
