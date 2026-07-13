import Foundation
import Testing
import LogicIR
import SystemVerilogFrontend
import PowerIntent
import XcircuitePackage

@Suite("LogicDesign execution")
struct EngineTests {
    @Test("elaboration returns a completed envelope for valid RTL")
    func elaborationCompletes() async throws {
        let source = SystemVerilogSourceUnit(
            path: "valid.sv",
            source: "module top(input logic a, output logic y); assign y = a; endmodule"
        )
        let request = LogicElaborationRequest(
            runID: "run-valid",
            inputs: [],
            topDesignName: "top",
            sources: [source]
        )
        let result = try await LogicElaboratingEngine(clock: { Date(timeIntervalSince1970: 0) }).execute(request)
        #expect(result.status == .completed)
        #expect(result.payload.snapshot?.designDigest != nil)
        #expect(result.payload.snapshot?.rtl.sourceFiles.first?.path == "valid.sv")
    }

    @Test("elaboration rejects an unverified filesystem request")
    func elaborationRejectsMissingInputIntegrity() async throws {
        let request = LogicElaborationRequest(
            runID: "run-unverified",
            inputs: [XcircuiteFileReference(path: "top.sv", kind: .rtl, format: .systemVerilog)],
            topDesignName: "top"
        )
        let result = try await LogicElaboratingEngine(clock: { Date(timeIntervalSince1970: 0) }).execute(request)
        #expect(result.status == .failed)
        #expect(result.diagnostics.contains { $0.code == "LOGIC_REQUEST_INPUT_INTEGRITY_MISSING" })
    }

    @Test("elaboration resolves relative includes and propagates macros")
    func elaborationResolvesIncludes() async throws {
        let source = SystemVerilogSourceUnit(
            path: "rtl/top.sv",
            source: "`include \"defs.svh\"\nmodule top(input logic [`WIDTH-1:0] a, output logic [`WIDTH-1:0] y); assign y = a; endmodule"
        )
        let provider = InMemorySystemVerilogSourceProvider(sources: [
            "rtl/defs.svh": "`define WIDTH 4\n"
        ])
        let request = LogicElaborationRequest(
            runID: "run-include",
            inputs: [],
            topDesignName: "top",
            sources: [source]
        )
        let result = try await LogicElaboratingEngine(
            sourceProvider: provider,
            clock: { Date(timeIntervalSince1970: 0) }
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.sourceUnitCount == 2)
        #expect(result.payload.snapshot?.rtl.sourceFiles.map(\.path) == ["rtl/defs.svh", "rtl/top.sv"])
        #expect(result.payload.snapshot?.rtl.modules.first?.ports.first?.range?.width == 4)
    }

    @Test("hierarchical instances flatten into a single canonical top module")
    func elaborationFlattensHierarchy() async throws {
        let source = SystemVerilogSourceUnit(
            path: "hierarchy.sv",
            source: """
            module leaf(input logic a, output logic y);
                assign y = a;
            endmodule
            module top(input logic a, output logic y);
                logic child_y;
                leaf u_leaf(.a(a), .y(child_y));
                assign y = child_y;
            endmodule
            """
        )
        let request = LogicElaborationRequest(
            runID: "run-hierarchy",
            inputs: [],
            topDesignName: "top",
            sources: [source]
        )

        let result = try await LogicElaboratingEngine(
            clock: { Date(timeIntervalSince1970: 0) }
        ).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.snapshot?.rtl.modules.count == 1)
        #expect(result.payload.snapshot?.rtl.modules.first?.instances.isEmpty == true)
        #expect(result.payload.snapshot?.rtl.modules.first?.assignments.count == 3)
        #expect(result.payload.snapshot?.rtl.modules.first?.signals.contains {
            $0.name == "u_leaf__y"
        } == true)
    }

    @Test("recursive hierarchy is blocked with a typed diagnostic")
    func recursiveHierarchyIsBlocked() async throws {
        let source = SystemVerilogSourceUnit(
            path: "recursive.sv",
            source: """
            module a(input logic value, output logic result);
                b u_b(.value(value), .result(result));
            endmodule
            module b(input logic value, output logic result);
                a u_a(.value(value), .result(result));
            endmodule
            """
        )
        let result = try await LogicElaboratingEngine(
            clock: { Date(timeIntervalSince1970: 0) }
        ).execute(LogicElaborationRequest(
            runID: "run-recursive-hierarchy",
            inputs: [],
            topDesignName: "a",
            sources: [source]
        ))

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code == "LOGIC_HIERARCHY_CYCLE" })
    }

    @Test("elaboration reports a missing include as a typed diagnostic")
    func elaborationReportsMissingInclude() async throws {
        let source = SystemVerilogSourceUnit(
            path: "rtl/top.sv",
            source: "`include \"missing.svh\"\nmodule top; endmodule"
        )
        let request = LogicElaborationRequest(
            runID: "run-missing-include",
            inputs: [],
            topDesignName: "top",
            sources: [source]
        )
        let result = try await LogicElaboratingEngine(
            sourceProvider: InMemorySystemVerilogSourceProvider(sources: [:]),
            clock: { Date(timeIntervalSince1970: 0) }
        ).execute(request)

        #expect(result.status == .failed)
        #expect(result.diagnostics.contains { $0.code == "SV_INCLUDE_MISSING" })
    }

    @Test("unsupported RTL is blocked")
    func elaborationBlocksUnsupported() async throws {
        let source = SystemVerilogSourceUnit(
            path: "unsupported.sv",
            source: "module top(input logic a, output logic y); generate if (a) begin : g assign y = a; end endgenerate endmodule"
        )
        let request = LogicElaborationRequest(
            runID: "run-blocked",
            inputs: [],
            topDesignName: "top",
            sources: [source]
        )
        let result = try await LogicElaboratingEngine(clock: { Date(timeIntervalSince1970: 0) }).execute(request)
        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code == "SV_UNSUPPORTED_GENERATE" })
    }

    @Test("constant generate-for blocks are expanded in the snapshot")
    func elaborationExpandsGenerateFor() async throws {
        let source = SystemVerilogSourceUnit(
            path: "generated.sv",
            source: "module top(input logic a, output logic y); generate for (genvar i = 0; i < 2; i = i + 1) begin : g assign y = a; end endgenerate endmodule"
        )
        let request = LogicElaborationRequest(
            runID: "run-generate",
            inputs: [],
            topDesignName: "top",
            sources: [source]
        )
        let result = try await LogicElaboratingEngine(clock: { Date(timeIntervalSince1970: 0) }).execute(request)
        #expect(result.status == .completed)
        #expect(result.payload.snapshot?.rtl.modules.first?.generateBlocks.isEmpty == true)
        #expect(result.payload.snapshot?.rtl.modules.first?.assignments.count == 2)
    }

    @Test("snapshot codec preserves identity and digest")
    func snapshotRoundTrip() throws {
        let design = RTLDesign(topModuleName: "top", modules: [RTLModule(id: "m1", name: "top")])
        let snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(rtl: design))
        let decoded = try LogicDesignSnapshotCodec.decode(LogicDesignSnapshotCodec.encode(snapshot))
        #expect(decoded == snapshot)
        #expect(try LogicDesignSnapshotCodec.digest(decoded) == snapshot.designDigest)
    }

    @Test("snapshot codec rejects a tampered digest")
    func snapshotRejectsTamperedDigest() throws {
        let design = RTLDesign(topModuleName: "top", modules: [RTLModule(id: "m1", name: "top")])
        var snapshot = try LogicDesignSnapshotCodec.finalized(LogicDesignSnapshot(rtl: design))
        snapshot.designDigest = String(repeating: "0", count: 64)
        let data = try LogicDesignSnapshotCodec.encode(snapshot)

        do {
            _ = try LogicDesignSnapshotCodec.decode(data)
            Issue.record("Expected snapshot decoding to reject the tampered digest")
        } catch let error as LogicDesignSnapshotCodecError {
            guard case .digestMismatch = error else {
                Issue.record("Expected a digest mismatch, got \(error)")
                return
            }
        }
    }

    @Test("power intent parser returns structured policies")
    func powerIntentParsing() async throws {
        let source = PowerIntentSourceUnit(
            path: "power.upf",
            source: """
            create_supply_set SS_A
            create_power_domain PD_A -elements {top} -supply_set SS_A
            set_domain_supply_net PD_A VDD_A
            set_isolation iso_a -domain PD_A -clamp_value 0 -isolation_signal iso
            set_retention ret_a -domain PD_A -retention_register state
            """,
            format: .upf
        )
        let reference = LogicDesignReference(
            artifact: XcircuiteFileReference(path: "design.json", kind: .rtl, format: .json),
            topDesignName: "top",
            designDigest: "design-digest"
        )
        let request = PowerIntentParsingRequest(
            runID: "run-power",
            inputs: [],
            design: reference,
            sources: [source]
        )
        let result = try await PowerIntentParsingEngine(clock: { Date(timeIntervalSince1970: 0) }).execute(request)
        #expect(result.status == .completed)
        #expect(result.payload.domainCount == 1)
        #expect(result.payload.intent?.isolationPolicies.count == 1)
        #expect(result.payload.intent?.retentionPolicies.count == 1)
    }
}
