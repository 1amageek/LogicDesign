import Foundation
import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicDesignSerialization
import LogicKernelProbeSupport
import SystemVerilogFrontend

@Suite(.timeLimit(.minutes(1)))
struct PublicSourceElaborationTests {
    private struct Deadline: LogicRunControlling {
        func checkpoint() throws(LogicKernelError) { throw .deadlineExceeded }
    }
    @available(macOS 26.0, *)
    private func context(work: UInt64 = 1_000_000_000, control: any LogicRunControlling = LogicCancellationSource()) throws -> LogicKernelContext {
        var maximums = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000_000)) })
        maximums[.workUnits] = work
        return LogicKernelContext(limits: try LogicKernelLimits(maximums: maximums), control: control)
    }
    @available(macOS 26.0, *)
    private func bundle(_ texts: [String], context: inout LogicKernelContext) throws -> LogicSourceBundle {
        var sources: [LogicSourceDocument] = []
        for index in texts.indices {
            let bytes = Array(texts[index].utf8)
            let id = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
                hexadecimalValue: LogicSourceDigest.sha256HexadecimalValue(of: Data(bytes))), byteCount: UInt64(bytes.count))
            sources.append(try LogicSourceDocument(logicalName: "s\(index).sv", artifactID: id, bytes: bytes, context: &context))
        }
        return try LogicSourceBundle(documents: sources, context: &context)
    }
    private func options(_ roots: [String], tokens: Int = 2000, top: String = "p") throws -> SystemVerilogElaborationOptions {
        try SystemVerilogElaborationOptions(roots: roots, top: top, maximumTokens: tokens,
            syntax: SystemVerilogSyntaxLimits(nodes: 2000, children: 4000, symbols: 1000, nesting: 60),
            rtl: RTLResolvedCapacity(signals: 100, expressions: 2000, operands: 4000, statements: 1000,
                children: 2000, caseItems: 100, caseMatches: 200, ports: 20, processes: 100), maximumNesting: 60)
    }
    @Test func publicExistentialCompilesModulesAcrossRootBoundariesAndResolvesHierarchy() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let sources = try bundle([
            "`define WIDTH 4\nmodule p(input [`WIDTH-1:0] a,b,output [`WIDTH:0] y);",
            "child #(.W(`WIDTH)) u(.a(a),.b(b),.y(y)); endmodule\n`include \"s2.sv\"",
            "module child #(parameter W=1)(input [W-1:0] a,b,output logic [W:0] y); always_comb begin y=0; for(int i=0;i<1;i++) y=a+b; end endmodule"], context: &run)
        let engine: any SystemVerilogElaborating = NativeSystemVerilogElaborator()
        let model = try engine.elaborate(sources, options: options(["s0.sv", "s1.sv"]), context: &run)
        for a in 0..<16 { for b in 0..<16 {
            #expect(try ProbeRTLProgramEvaluator.evaluate(model, inputs: ["a": a, "b": b], context: &run)["y"] == a+b)
        } }
        #expect(SystemVerilogElaborationOptions.profileIdentifier == "systemverilog.synthesis.v1")
    }
    @Test func signedValuesAtomicAssignmentsCaseAndStaticGenerateRetainBehavior() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let sources = try bundle(["module p(input signed [3:0] a,output logic [3:0] y,output logic [7:0] z); if(1) begin:g always_comb begin y=a; {y[3:2],y[1:0]}={y[1:0],y[3:2]}; case(a) -1:z=8'hff; default:z=a; endcase end end endmodule"], context: &run)
        let model = try NativeSystemVerilogElaborator().elaborate(sources, options: options(["s0.sv"]), context: &run)
        for a in 0..<16 {
            let outputs = try ProbeRTLProgramEvaluator.evaluate(model, inputs: ["a": a], context: &run)
            #expect(outputs["y"] == ((a & 3) << 2) | (a >> 2))
            #expect(outputs["z"] == (a >= 8 ? a+240 : a))
        }
    }
    @Test func invalidLanguageAndStateProfilesHaveOriginalSourceLocations() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        let sources = [
            "module p(input [3:0] a,b,output [3:0] y);assign y=a/b;endmodule",
            "package p; endpackage",
            "interface p; endinterface",
            "module p(output y);reg mem[0:3];assign y=mem[0];endmodule",
            "module p(input c1,c2,d,output logic q1,q2);always_ff @(posedge c1)q1<=d;always_ff @(posedge c2)q2<=d;endmodule",
            "module p(input c,d,en,output logic q,l);always_ff @(posedge c)q<=d;always_latch if(en)l=d;endmodule",
            "module p(input a);always_comb a=0;endmodule",
            "module p(output y);assign y=0;assign y=1;endmodule"]
        for source in sources {
            var run = try context(); let input = try bundle([source], context: &run)
            do {
                _ = try NativeSystemVerilogElaborator().elaborate(input, options: options(["s0.sv"]), context: &run)
                Issue.record("Unsupported source was accepted")
            } catch let error as LogicKernelError {
                guard case .sourceFailure(_, let origin, _) = error else { Issue.record("Missing located failure: \(error)"); continue }
                #expect(origin.artifactID == (try input.document(at: 0)).artifactID)
                #expect(origin.byteRange.upperBound <= UInt64(source.utf8.count))
            }
        }
    }
    @Test func macroUnknownValuesAndSecondRootDriverErrorsPointToActualInputs() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let input = try bundle(["`define BAD 1'bx\n", "module p(output y);assign y=`BAD;endmodule"], context: &run)
        do {
            _ = try NativeSystemVerilogElaborator().elaborate(input, options: options(["s0.sv", "s1.sv"]), context: &run)
            Issue.record("Synthesis X was accepted")
        } catch let error as LogicKernelError {
            guard case .sourceFailure(let code, let origin, _) = error else { Issue.record("Missing macro source failure"); return }
            #expect(code.rawValue == "SV_SYNTHESIS_XZ_LITERAL")
            #expect(origin == (try LogicKernelSourceRange(artifactID: input.document(at: 1).artifactID, byteRange: 28..<32)))
        }
        let drivers = try bundle(["module p(output y);assign y=0;", "assign y=1;endmodule"], context: &run)
        do {
            _ = try NativeSystemVerilogElaborator().elaborate(drivers, options: options(["s0.sv", "s1.sv"]), context: &run)
            Issue.record("Multiple drivers were accepted")
        } catch let error as LogicKernelError {
            guard case .sourceFailure(let code, let origin, _) = error else { Issue.record("Missing driver source failure"); return }
            #expect(code.rawValue == "LOGIC_RTL_MULTIPLE_DRIVERS")
            #expect(origin.artifactID == (try drivers.document(at: 1)).artifactID)
        }
    }
    @Test func cumulativeWorkBudgetCancellationDeadlineAndCapacityNeverBecomeSuccess() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var setup = try context()
        let input = try bundle(["module p(input a,output y);assign y=a;endmodule"], context: &setup)
        let settings = try options(["s0.sv"])
        var measurement = try context()
        _ = try NativeSystemVerilogElaborator().elaborate(input, options: settings, context: &measurement)
        let required = measurement.usage[.workUnits]
        var bounded = try context(work: required-1)
        do {
            _ = try NativeSystemVerilogElaborator().elaborate(input, options: settings, context: &bounded)
            Issue.record("Stages reset the cumulative work budget")
        } catch {
            guard case .resourceLimit(let resource, _, _) = error else { Issue.record("Expected resource failure"); return }
            #expect(resource == .workUnits)
        }
        let cancellation = LogicCancellationSource(); cancellation.cancel()
        for control: any LogicRunControlling in [cancellation, Deadline()] {
            var run = try context(control: control)
            #expect(throws: LogicKernelError.self) {
                try NativeSystemVerilogElaborator().elaborate(input, options: settings, context: &run)
            }
            #expect(run.usage[.managedStorageBytes] == 0)
        }
        var run = try context()
        #expect(throws: LogicKernelError.self) {
            try NativeSystemVerilogElaborator().elaborate(input, options: options(["s0.sv"], tokens: 2), context: &run)
        }
    }
    @Test func invalidOptionsRootSelectionAndAbsentTopAreTypedInputFailures() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        #expect(throws: LogicKernelError.self) { try options([]) }
        #expect(throws: LogicKernelError.self) { try options(["s0.sv"], tokens: 0) }
        var run = try context(); let input = try bundle(["module p;endmodule"], context: &run)
        for roots in [["missing"], ["s0.sv", "s0.sv"]] {
            #expect(throws: LogicKernelError.self) {
                try NativeSystemVerilogElaborator().elaborate(input, options: options(roots), context: &run)
            }
        }
        #expect(throws: LogicKernelError.self) {
            try NativeSystemVerilogElaborator().elaborate(input, options: options(["s0.sv"], top: "absent"), context: &run)
        }
    }
    @Test func portablePublicCompositionProbeExecutesSuccessAndRefusal() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        try exercisePublicSourceElaborationContract()
    }
}
