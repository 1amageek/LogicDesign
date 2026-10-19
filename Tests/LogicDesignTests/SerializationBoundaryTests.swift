import Foundation
import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicDesignSerialization

@Suite(.timeLimit(.minutes(1)))
struct SerializationBoundaryTests {
    private struct Control: LogicRunControlling {
        func checkpoint() throws(LogicKernelError) {}
    }
    private func context() throws -> LogicKernelContext {
        LogicKernelContext(limits: try LogicKernelLimits(maximums: Dictionary(
            uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) }
        )), control: Control())
    }
    private func id(_ value: UInt64) throws -> DesignEntityID { try DesignEntityID(rawValue: value) }

    @available(macOS 26.0, *)
    private func encodedSequentialDesign() throws -> Data {
        var context = try context()
        var builder = try BitLogicBuilder(capacity: BitGraphCapacity(nodes: 3, operands: 0,
            ports: 2, portBits: 3, states: 1), context: &context)
        let clock = try builder.addNode(id: id(1), operation: .input, context: &context)
        let data = try builder.addNode(id: id(2), operation: .input, context: &context)
        let q = try builder.addNode(id: id(3), operation: .state(BitStateIndex(0)), context: &context)
        let artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
            hexadecimalValue: String(repeating: "a", count: 64)), byteCount: 100)
        let origin = try LogicKernelSourceRange(artifactID: artifact, byteRange: 3..<10)
        _ = try builder.addState(BitLogicState(id: id(1), next: data,
            control: .flipFlop(clock: clock, edge: .falling, enable: data,
                reset: BitReset(signal: data, activeHigh: false, value: true, kind: .asynchronous)),
            initialValue: nil, origin: origin), context: &context)
        try builder.addPort(id: id(1), direction: .input, bits: [clock, data], context: &context)
        try builder.addPort(id: id(2), direction: .output, bits: [q], context: &context)
        let design = try builder.finish(context: &context)
        return try BitLogicDesignCodec().encode(design)
    }

    @Test func exactBitGraphRoundTripPreservesStateAndSource() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        let data = try encodedSequentialDesign()
        var context = try context()
        let codec: any BitLogicDesignCoding = BitLogicDesignCodec()
        let decoded = try codec.decode(data, context: &context)
        #expect(try codec.encode(decoded) == data)
        #expect(decoded.withTables { _, _, _, _, states, _ in
            states[0].initialValue == nil && states[0].origin?.byteRange == 3..<10
        })
    }

    @Test func decodingCannotBypassGraphAdmission() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        let data = try encodedSequentialDesign()
        let canonical = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for mutation in 0..<5 {
            var object = canonical
            switch mutation {
            case 0: object["schemaVersion"] = 99
            case 1: object["portBits"] = [0, 1, 999]
            case 2:
                var nodes = try #require(object["nodes"] as? [[String: Any]])
                nodes[0]["operandCount"] = Int.max; object["nodes"] = nodes
            case 3:
                var states = try #require(object["states"] as? [[String: Any]])
                states[0]["next"] = -1; object["states"] = states
            default:
                var states = try #require(object["states"] as? [[String: Any]])
                var origin = try #require(states[0]["origin"] as? [String: Any])
                origin["end"] = 101; states[0]["origin"] = origin; object["states"] = states
            }
            let malformed = try JSONSerialization.data(withJSONObject: object)
            var context = try context()
            #expect(throws: LogicKernelError.self) { try BitLogicDesignCodec().decode(malformed, context: &context) }
        }
    }

    @Test func oldBitVectorDecoderRejectsTailBitsAndOverflowWidths() throws {
        for text in [#"{"width":1,"bytes":[255]}"#, #"{"width":9223372036854775807,"bytes":[]}"#] {
            #expect(throws: LogicBitVectorError.self) {
                try JSONDecoder().decode(LogicBitVector.self, from: Data(text.utf8))
            }
        }
    }

    @Test func fourStateVectorRoundTripAndMalformedPlanes() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        let vector = try LogicFourStateVector(width: LogicBitWidth(129),
                                             valueWords: [1, 0, 1], unknownWords: [0, .max, 1])
        let encoded = try JSONEncoder().encode(vector)
        #expect(try JSONDecoder().decode(LogicFourStateVector.self, from: encoded) == vector)
        for text in [#"{"schemaVersion":1,"width":1,"valueWords":[2],"unknownWords":[0]}"#,
                     #"{"schemaVersion":1,"width":65,"valueWords":[0],"unknownWords":[0]}"#] {
            #expect(throws: LogicKernelError.self) {
                try JSONDecoder().decode(LogicFourStateVector.self, from: Data(text.utf8))
            }
        }
    }

    @Test func snapshotDecoderAlsoValidatesModel() throws {
        let invalid = LogicDesignSnapshot(rtl: RTLDesign(topModuleName: "missing", modules: []))
        let bytes = try LogicDesignSnapshotCodec.encode(invalid)
        #expect(throws: LogicDesignSnapshotCodecError.self) { try LogicDesignSnapshotCodec.decode(bytes) }
    }
    @Test func gateOnlyDraftValidatesItsPresentRepresentation() throws {
        let gate = GateDesign(topModuleName: "top", modules: [GateModule(id: "top", name: "top")])
        let draft = LogicDesignSnapshot(rtl: RTLDesign(topModuleName: "top"), gate: gate)
        let decoded = try LogicDesignSnapshotCodec.decode(LogicDesignSnapshotCodec.encode(draft))
        #expect(decoded.rtl.modules.isEmpty)
        #expect(decoded.gate == gate)
        var invalid = draft
        invalid.gate?.topModuleName = "missing"
        #expect(throws: LogicDesignSnapshotCodecError.self) {
            try LogicDesignSnapshotCodec.decode(LogicDesignSnapshotCodec.encode(invalid))
        }
        invalid = draft
        invalid.rtl.modules = [RTLModule(id: "other", name: "other")]
        #expect(throws: LogicDesignSnapshotCodecError.self) {
            try LogicDesignSnapshotCodec.decode(LogicDesignSnapshotCodec.encode(invalid))
        }
    }

}
