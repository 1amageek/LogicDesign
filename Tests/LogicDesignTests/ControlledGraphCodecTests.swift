import Foundation
import Synchronization
import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicDesignSerialization

@Suite(.timeLimit(.minutes(1)))
struct ControlledGraphCodecTests {
    private struct Control: LogicRunControlling { func checkpoint() throws(LogicKernelError) {} }
    @available(macOS 26.0, *)
    private final class Accountant: LogicKernelAccounting {
        struct State { var live: UInt64 = 0; var peak: UInt64 = 0; var work: UInt64 = 0; var allocations: UInt64 = 0 }
        let state = Mutex(State())
        let maximum: UInt64
        init(maximum: UInt64 = 10_000_000) { self.maximum = maximum }
        func observeBitWidth(_ width: UInt64) throws(LogicKernelError) {}
        func charge(_ resource: LogicResource, amount: UInt64) throws(LogicKernelError) { state.withLock { $0.work += amount } }
        func reserveStorage(byteCount: UInt64) throws(LogicKernelError) -> any LogicKernelStorageRetaining {
            let refused = state.withLock { value in
                let sum = value.live.addingReportingOverflow(byteCount)
                if sum.overflow || sum.partialValue > maximum { return true }
                value.live = sum.partialValue; value.peak = max(value.peak, value.live); value.allocations += byteCount
                return false
            }
            if refused { throw .externalAccountingFailure }
            return Lease(owner: self, bytes: byteCount)
        }
        private final class Lease: LogicKernelStorageRetaining {
            let owner: Accountant; let bytes: UInt64
            init(owner: Accountant, bytes: UInt64) { self.owner = owner; self.bytes = bytes }
            deinit { owner.state.withLock { $0.live -= bytes } }
        }
    }
    @available(macOS 26.0, *)
    private func context(_ owner: Accountant? = nil, work: UInt64 = 10_000_000) throws -> LogicKernelContext {
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(10_000_000)) })
        limits[.workUnits] = work
        if let owner { return .init(limits: try .init(maximums: limits), control: Control(), accounting: owner) }
        return .init(limits: try .init(maximums: limits), control: Control())
    }
    @available(macOS 26.0, *)
    private func id(_ value: UInt64) throws -> DesignEntityID { try .init(rawValue: value) }
    @available(macOS 26.0, *)
    private func artifact() throws -> ArtifactID {
        try .init(digest: .init(algorithm: .sha256, hexadecimalValue: String(repeating: "ab", count: 32)), byteCount: 1000)
    }
    @available(macOS 26.0, *)
    private func bit(_ mode: Int, context: inout LogicKernelContext) throws -> BitLogicDesign {
        let origin = try LogicKernelSourceRange(artifactID: artifact(), byteRange: 10..<20)
        var builder = try BitLogicBuilder(capacity: .init(nodes: 4, operands: 1, ports: 2, portBits: 3, states: mode == 0 ? 0 : 1), context: &context)
        let data = try builder.addNode(id: id(1), operation: .input, origin: origin, context: &context)
        let clock = try builder.addNode(id: id(2), operation: .input, context: &context)
        let output: BitNodeIndex
        if mode == 0 { output = try builder.addNode(id: id(3), operation: .invert, inputs: [data], context: &context) }
        else {
            output = try builder.addNode(id: id(3), operation: .state(.init(0)), context: &context)
            let reset: BitReset? = mode == 3 ? nil : BitReset(signal: data, activeHigh: true, value: false, kind: mode == 2 ? .asynchronous : .synchronous)
            let control: BitStateControl = mode == 2 ? .latch(gate: clock, activeHigh: true, reset: reset) : .flipFlop(clock: clock, edge: .rising, enable: mode == 3 ? nil : data, reset: reset)
            _ = try builder.addState(.init(id: id(9), next: data, control: control, initialValue: mode == 3 ? nil : false, origin: mode == 3 ? nil : origin), context: &context)
        }
        _ = try builder.addNode(id: id(4), operation: .constant(true), context: &context)
        try builder.addPort(id: id(10), direction: .input, bits: [data, clock], context: &context)
        try builder.addPort(id: id(11), direction: .output, bits: [output], context: &context)
        return try builder.finish(context: &context)
    }
    @available(macOS 26.0, *)
    private func mapped(sequential: Bool, context: inout LogicKernelContext) throws -> MappedGateDesign {
        let pinCount = sequential ? 4 : 2
        var function = try LogicBooleanFunctionBuilder(inputCount: pinCount + (sequential ? 1 : 0), nodeCapacity: 1, context: &context)
        let input = try function.append(.input(sequential ? pinCount : 0), context: &context)
        let value = try function.finish(output: input, context: &context)
        var cell = try LogicTechnologyCellBuilder(id: id(100), name: "buf_é\\\"\n\u{2028}\u{2029}", pinCapacity: pinCount, context: &context)
        _ = try cell.append(.init(id: id(101), name: "A😀", direction: .input), context: &context)
        if sequential {
            _ = try cell.append(.init(id: id(102), name: "CK", direction: .input), context: &context)
            _ = try cell.append(.init(id: id(103), name: "RN", direction: .input), context: &context)
        }
        _ = try cell.append(.init(id: id(104), name: "Yé", direction: .output, function: value), context: &context)
        let state: LogicCellStateDefinition?
        if sequential {
            var next = try LogicBooleanFunctionBuilder(inputCount: pinCount + 1, nodeCapacity: 1, context: &context)
            let data = try next.append(.input(0), context: &context)
            state = .init(control: .flipFlop(clock: .init(1), risingEdge: true),
                nextState: try next.finish(output: data, context: &context),
                asynchronousReset: .init(pin: .init(2), activeHigh: false, value: false))
        } else { state = nil }
        var library = try LogicTechnologyLibraryBuilder(cellCapacity: 1, totalPinCapacity: pinCount, context: &context)
        _ = try library.append(cell.finish(area: 1, state: state, context: &context), context: &context)
        let lib = try library.finish(source: artifact(), context: &context)
        var builder = try MappedGateBuilder(library: lib, capacity: .init(nets: sequential ? 5 : 3, instances: 1, pinConnections: pinCount, ports: 2, portBits: sequential ? 4 : 2), context: &context)
        let origin = try LogicKernelSourceRange(artifactID: artifact(), byteRange: 10..<20)
        let y = try builder.addNet(.init(id: id(1), driver: .instanceOutput(.init(0), .init(pinCount - 1)), origin: origin), context: &context)
        let a = try builder.addNet(.init(id: id(2), driver: .input), context: &context)
        _ = try builder.addNet(.init(id: id(3), driver: .constant(true)), context: &context)
        var inputs = [a]
        if sequential {
            let clock = try builder.addNet(.init(id: id(4), driver: .input), context: &context)
            let reset = try builder.addNet(.init(id: id(5), driver: .input), context: &context)
            inputs.append(clock); inputs.append(reset)
        }
        let stateID: DesignEntityID? = sequential ? try id(50) : nil
        _ = try builder.addInstance(id: id(10), cell: .init(0), pinNets: inputs + [y],
            stateID: stateID, initialValue: sequential ? false : nil,
            origin: origin, context: &context)
        try builder.addPort(id: id(20), direction: .input, nets: inputs, context: &context)
        try builder.addPort(id: id(21), direction: .output, nets: [y], context: &context)
        return try builder.finish(context: &context)
    }
    @Test(arguments: [0, 1, 2, 3]) func bitBytesAndOriginalStateMeaningArePreserved(_ mode: Int) throws {
        guard #available(macOS 26.0, *) else { Issue.record("Controlled contract verification requires macOS 26.0"); return }
        var original = try context(); let design = try bit(mode, context: &original)
        let codec: any BitLogicDesignControlledCoding = BitLogicDesignCodec()
        let bytes = try codec.encode(design)
        let owner = Accountant(); var controlled = try context(owner)
        let encoded = try codec.encodeControlled(design, context: &controlled)
        #expect(encoded.value == bytes)
        let decoded = try codec.decodeControlled(bytes, context: &controlled)
        #expect(try codec.encode(decoded.value) == bytes)
        let semantics = decoded.value.withTables { nodes, _, ports, _, states, _ in
            nodes.count == 4 && ports.count == 2 && states.count == (mode == 0 ? 0 : 1)
        }
        #expect(semantics)
        withExtendedLifetime((encoded.retention, decoded.retention)) { #expect(owner.state.withLock { $0.live } > 0) }
    }
    @Test(arguments: [false, true]) func mappedUnicodeEscapesAndExactLibraryBindingRoundTrip(_ sequential: Bool) throws {
        guard #available(macOS 26.0, *) else { Issue.record("Controlled contract verification requires macOS 26.0"); return }
        var original = try context(); let graph = try mapped(sequential: sequential, context: &original)
        let codec: any MappedGateDesignControlledCoding = MappedGateDesignCodec()
        let bytes = try codec.encode(graph)
        let owner = Accountant(); var controlled = try context(owner)
        let encoded = try codec.encodeControlled(graph, context: &controlled)
        #expect(encoded.value == bytes)
        let decoded = try codec.decodeControlled(bytes, library: graph.library, context: &controlled)
        #expect(try codec.encode(decoded.value) == bytes)
        // This spelling is not canonical output, but represents the same original pin.
        let escaped = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "😀", with: "\\uD83D\\uDE00")
        let alternate = try codec.decodeControlled(Data(escaped.utf8), library: graph.library, context: &controlled)
        #expect(try codec.encode(alternate.value) == bytes)
        let semantics = decoded.value.withTables { nets, instances, pins, ports, _, _ in
            nets.count == (sequential ? 5 : 3) && instances.count == 1 && pins.count == (sequential ? 4 : 2) && ports.count == 2
        }
        #expect(semantics)
        withExtendedLifetime((encoded.retention, decoded.retention, alternate.retention)) {}
    }
    @Test func explicitControlledProfileRefusesMalformedDuplicateAndOtherEncoding() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Controlled contract verification requires macOS 26.0"); return }
        var original = try context(); let graph = try bit(0, context: &original)
        let codec = BitLogicDesignCodec(); let bytes = try codec.encode(graph)
        let text = String(decoding: bytes, as: UTF8.self)
        let duplicate = text.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1,\"schemaVersion\":1")
        let nonUTF8 = try #require(text.data(using: .utf16))
        func checkProfileFailure(_ invalid: Data, owner: Accountant) throws {
            var controlled = try context(owner)
            do { _ = try codec.decodeControlled(invalid, context: &controlled); Issue.record("Controlled malformed/profile input passed") }
            catch let failure as LogicGraphCodecSourceFailure {
                let cause = try #require(failure.cause as? LogicKernelError)
                guard case .invalidInput = cause else { Issue.record("Unexpected profile refusal: \(cause)"); return }
                withExtendedLifetime(failure.retention) { #expect(owner.state.withLock { $0.live } > 0) }
            }
        }
        for invalid in [Data("{".utf8), Data(duplicate.utf8), nonUTF8] {
            let owner = Accountant()
            try checkProfileFailure(invalid, owner: owner)
            #expect(owner.state.withLock { $0.live } == 0)
        }
        // The new profile does not remove the legacy Foundation encoding surface.
        var legacy = try context()
        #expect(try codec.encode(codec.decode(nonUTF8, context: &legacy)) == bytes)
        let unknown = "{\"ignored\":{\"text\":\"é\"}," + text.dropFirst()
        let owner = Accountant(); var controlled = try context(owner)
        let result = try codec.decodeControlled(Data(unknown.utf8), context: &controlled)
        #expect(try codec.encode(result.value) == bytes)
        withExtendedLifetime(result.retention) {}
    }
    @Test func limitsCancellationAndCopiesRetainOnlyTheirExplicitAnchor() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Controlled contract verification requires macOS 26.0"); return }
        var original = try context(); let graph = try bit(0, context: &original)
        let codec = BitLogicDesignCodec(); let bytes = try codec.encode(graph)
        let refused = Accountant(maximum: 1); var insufficient = try context(refused)
        #expect(throws: LogicKernelError.externalAccountingFailure) { _ = try codec.decodeControlled(bytes, context: &insufficient) }
        #expect(refused.state.withLock { $0.live } == 0)
        let workOwner = Accountant(); var tiny = try context(workOwner, work: 1)
        #expect(throws: LogicKernelError.self) { _ = try codec.decodeControlled(bytes, context: &tiny) }
        #expect(workOwner.state.withLock { $0.live } == 0)
        var noHook = try context()
        #expect(throws: LogicKernelError.self) { _ = try codec.decodeControlled(bytes, context: &noHook) }
        let owner = Accountant()
        func decode() throws -> (value: BitLogicDesign, retention: LogicKernelRetention) {
            var run = try context(owner)
            return try codec.decodeControlled(bytes, context: &run)
        }
        var first: (value: BitLogicDesign, retention: LogicKernelRetention)? = try decode()
        var second = first
        first = nil
        withExtendedLifetime(second) { #expect(owner.state.withLock { $0.live } > 0) }
        second = nil
        #expect(owner.state.withLock { $0.live } == 0)
    }
    @Test func originalArtifactFailurePayloadAndCopiedAnchorSurviveCancellation() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Controlled contract verification requires macOS 26.0"); return }
        var original = try context(); let graph = try bit(0, context: &original)
        let codec = BitLogicDesignCodec(); let bytes = try codec.encode(graph)
        let valid = try artifact().description
        // Keep canonical lengths intact; the original CF constructor rejects the
        // source-derived algorithm token and retains its offending String.
        let invalid = valid.replacingOccurrences(of: "736861323536", with: "206861323536")
        let bad = Data(String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: valid, with: invalid).utf8)
        let owner = Accountant(); let cancellation = LogicCancellationSource()
        func sourceFailure() throws -> LogicGraphCodecSourceFailure {
            let limits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(10_000_000)) }))
            var run = LogicKernelContext(limits: limits, control: cancellation, accounting: owner)
            do { _ = try codec.decodeControlled(bad, context: &run) }
            catch let failure as LogicGraphCodecSourceFailure { return failure }
            throw LogicKernelError.invalidModel("The invalid original ArtifactID unexpectedly passed")
        }
        var first: LogicGraphCodecSourceFailure? = try sourceFailure()
        var second = first
        first = nil
        cancellation.cancel()
        do {
            let copied = try #require(second)
            let cause = try #require(copied.cause as? ArtifactIDError)
            #expect(cause == .invalidDigestAlgorithm(.leadingOrTrailingWhitespace(kind: "Content digest algorithm", value: " ha256")))
            withExtendedLifetime(copied.retention) { #expect(owner.state.withLock { $0.live } > 0) }
        }
        second = nil
        #expect(owner.state.withLock { $0.live } == 0)
    }

}
