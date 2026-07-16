import Foundation
import Testing
import LogicIR
import SystemVerilogFrontend
import PowerIntent
import CircuiteFoundation

@Suite("LogicDesign execution")
struct EngineTests {
    @Test("elaboration returns a completed domain result for valid RTL")
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

    @Test("elaboration reports a missing filesystem input")
    func elaborationRejectsMissingInputIntegrity() async throws {
        let request = LogicElaborationRequest(
            runID: "run-unverified",
            inputs: [ArtifactLocator(path: "top.sv", kind: .rtl, format: .systemVerilog)],
            topDesignName: "top"
        )
        let result = try await LogicElaboratingEngine(clock: { Date(timeIntervalSince1970: 0) }).execute(request)
        #expect(result.status == .failed)
        #expect(result.logicDiagnostics.contains { $0.code == "SV_SOURCE_LOAD_FAILED" })
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
        #expect(result.logicDiagnostics.contains { $0.code == "LOGIC_HIERARCHY_CYCLE" })
    }

    @Test("hierarchy parameter overrides resolve port widths")
    func hierarchyParameterOverrideResolvesPortWidths() async throws {
        let source = SystemVerilogSourceUnit(
            path: "parameterized-hierarchy.sv",
            source: """
            module leaf #(parameter WIDTH = 1) (
                input logic [WIDTH-1:0] a,
                output logic [WIDTH-1:0] y
            );
                assign y = a;
            endmodule
            module top(input logic [3:0] a, output logic [3:0] y);
                leaf #(.WIDTH(4)) u_leaf(.a(a), .y(y));
            endmodule
            """
        )
        let result = try await LogicElaboratingEngine(
            clock: { Date(timeIntervalSince1970: 0) }
        ).execute(LogicElaborationRequest(
            runID: "run-parameterized-hierarchy",
            inputs: [],
            topDesignName: "top",
            sources: [source]
        ))

        #expect(result.status == .completed)
        let module = result.payload.snapshot?.rtl.modules.first
        #expect(module?.ports.first(where: { $0.name == "y" })?.range?.width == 4)
        #expect(module?.signals.first(where: { $0.name == "u_leaf__y" })?.range?.width == 4)
        #expect(module?.assignments.contains {
            if case .identifier(let target) = $0.target {
                return target == "u_leaf__y"
            }
            return false
        } == true)
    }

    @Test("hierarchy parameter overrides re-evaluate generate bounds")
    func hierarchyParameterOverrideReevaluatesGenerateBounds() async throws {
        let source = SystemVerilogSourceUnit(
            path: "parameterized-generate.sv",
            source: """
            module leaf #(parameter COUNT = 1) (
                input logic a,
                output logic y
            );
                wire [COUNT-1:0] bits;
                generate
                    for (genvar i = 0; i < COUNT; i = i + 1) begin : g
                        assign bits[i] = a;
                    end
                endgenerate
                assign y = a;
            endmodule
            module top(input logic a, output logic y);
                leaf #(.COUNT(3)) u_leaf(.a(a), .y(y));
            endmodule
            """
        )
        let result = try await LogicElaboratingEngine(
            clock: { Date(timeIntervalSince1970: 0) }
        ).execute(LogicElaborationRequest(
            runID: "run-parameterized-generate",
            inputs: [],
            topDesignName: "top",
            sources: [source]
        ))

        #expect(result.status == .completed)
        let module = result.payload.snapshot?.rtl.modules.first
        #expect(module?.signals.first(where: { $0.name == "u_leaf__bits" })?.range?.width == 3)
        #expect(module?.assignments.filter {
            if case .index(let value, _) = $0.target,
               case .identifier(let name) = value {
                return name == "u_leaf__bits"
            }
            return false
        }.count == 3)
    }

    @Test("hierarchy flattening supports indexed output connections and inout nets")
    func hierarchySupportsIndexedOutputsAndInout() async throws {
        let source = SystemVerilogSourceUnit(
            path: "indexed-output.sv",
            source: """
            module leaf(input logic a, output logic y, inout wire io);
                assign y = a;
                assign io = a;
            endmodule
            module top(input logic a, output logic [1:0] y, inout wire io);
                leaf u_leaf(.a(a), .y(y[0]), .io(io));
            endmodule
            """
        )
        let result = try await LogicElaboratingEngine(
            clock: { Date(timeIntervalSince1970: 0) }
        ).execute(LogicElaborationRequest(
            runID: "run-indexed-output",
            inputs: [],
            topDesignName: "top",
            sources: [source]
        ))

        #expect(result.status == .completed)
        #expect(result.logicDiagnostics.isEmpty)
        #expect(result.payload.snapshot?.rtl.modules.first?.assignments.contains {
            if case .index(let value, _) = $0.target,
               case .identifier(let name) = value {
                return name == "y"
            }
            return false
        } == true)
        #expect(result.payload.snapshot?.rtl.modules.first?.assignments.contains {
            if case .identifier(let name) = $0.target { return name == "io" }
            return false
        } == true)
    }

    @Test("hierarchy flattening resolves parameterized memories")
    func hierarchySupportsParameterizedMemories() async throws {
        let source = SystemVerilogSourceUnit(
            path: "memory-hierarchy.sv",
            source: """
            module leaf #(parameter WIDTH = 2, parameter DEPTH = 4) (
                input logic [1:0] address,
                output logic [WIDTH-1:0] value
            );
                logic [WIDTH-1:0] memory [0:DEPTH-1];
                assign value = memory[address];
            endmodule
            module top(input logic [1:0] address, output logic [1:0] value);
                leaf #(.WIDTH(2), .DEPTH(8)) u_leaf(.address(address), .value(value));
            endmodule
            """
        )
        let result = try await LogicElaboratingEngine(
            clock: { Date(timeIntervalSince1970: 0) }
        ).execute(LogicElaborationRequest(
            runID: "run-memory-hierarchy",
            inputs: [],
            topDesignName: "top",
            sources: [source]
        ))

        #expect(result.status == .completed)
        let module = result.payload.snapshot?.rtl.modules.first
        #expect(module?.memories.first(where: { $0.name == "u_leaf__memory" })?.addressRange == LogicRange(msb: 0, lsb: 7))
        #expect(module?.assignments.contains {
            if case .index(let value, _) = $0.value,
               case .identifier(let name) = value {
                return name == "u_leaf__memory"
            }
            return false
        } == true)
    }

    @Test("unknown hierarchy parameter overrides are blocked with a typed diagnostic")
    func unknownHierarchyParameterOverrideIsBlocked() async throws {
        let source = SystemVerilogSourceUnit(
            path: "unknown-parameter.sv",
            source: """
            module leaf #(parameter WIDTH = 1) (
                input logic [WIDTH-1:0] a,
                output logic [WIDTH-1:0] y
            );
                assign y = a;
            endmodule
            module top(input logic a, output logic y);
                leaf #(.UNKNOWN(4)) u_leaf(.a(a), .y(y));
            endmodule
            """
        )
        let result = try await LogicElaboratingEngine(
            clock: { Date(timeIntervalSince1970: 0) }
        ).execute(LogicElaborationRequest(
            runID: "run-unknown-parameter",
            inputs: [],
            topDesignName: "top",
            sources: [source]
        ))

        #expect(result.status == .blocked)
        #expect(result.logicDiagnostics.contains {
            $0.code == "LOGIC_HIERARCHY_PARAMETER_UNRESOLVED" &&
            $0.entity == "top.u_leaf.UNKNOWN"
        })
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
        #expect(result.logicDiagnostics.contains { $0.code == "SV_INCLUDE_MISSING" })
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
        #expect(result.logicDiagnostics.contains { $0.code == "SV_UNSUPPORTED_GENERATE" })
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
            create_supply_set SS_A -supply_net {VDD_A VSS_A}
            create_power_domain PD_A -elements {top} -supply_set SS_A
            set_domain_supply_net PD_A VDD_A
            set_isolation iso_a -domain PD_A -clamp_value 0 -isolation_signal iso
            set_retention ret_a -domain PD_A -retention_register state
            """,
            format: .upf
        )
        let reference = LogicDesignReference(
            artifact: ArtifactReference(
                locator: ArtifactLocator(path: "design.json", kind: .rtl, format: .json),
                digest: try ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: String(repeating: "3", count: 64)
                ),
                byteCount: 128
            ),
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
        #expect(result.payload.intent?.supplySets.first?.supplyNets == ["VDD_A", "VSS_A"])
        #expect(result.payload.intent?.structuredDirectives.first?.arguments == ["SS_A"])
        #expect(result.payload.intent?.isolationPolicies.count == 1)
        #expect(result.payload.intent?.retentionPolicies.count == 1)
        #expect(result.payload.intent?.structuredDirectives.count == 5)
        if let intent = result.payload.intent {
            let data = try JSONEncoder().encode(intent)
            let decoded = try JSONDecoder().decode(PowerIntentDesign.self, from: data)
            #expect(decoded == intent)
        }
    }
}
