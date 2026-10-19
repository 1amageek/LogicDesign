import Foundation
import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicDesignSerialization
import LogicKernelProbeSupport
@testable import SystemVerilogFrontend

@Suite(.timeLimit(.minutes(1)))
struct ProgramElaborationTests {
    @available(macOS 26.0, *)
    private func context(_ maximum: UInt64 = 100_000_000) throws -> LogicKernelContext {
        LogicKernelContext(limits: try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
            LogicResource.allCases.map { ($0, maximum) })), control: LogicCancellationSource())
    }
    @available(macOS 26.0, *)
    private func syntax(_ text: String, name: String, context: inout LogicKernelContext) throws -> SystemVerilogSyntaxTree {
        let bytes = Array(text.utf8)
        let artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
            hexadecimalValue: LogicSourceDigest.sha256HexadecimalValue(of: Data(bytes))), byteCount: UInt64(bytes.count))
        let source = try LogicSourceDocument(logicalName: name, artifactID: artifact, bytes: bytes, context: &context)
        let tokens = try SystemVerilogByteLexer().tokenize(source, maximumTokens: bytes.count + 1, context: &context)
        return try SystemVerilogSyntaxParser.parse(tokens, limits: SystemVerilogSyntaxLimits(nodes: bytes.count,
            children: bytes.count, symbols: bytes.count, nesting: 100), context: &context)
    }
    @available(macOS 26.0, *)
    private func compile(_ sources: [String], top: String = "p", context: inout LogicKernelContext) throws -> ElaboratedRTL {
        var trees: [SystemVerilogSyntaxTree] = []
        for index in sources.indices { trees.append(try syntax(sources[index], name: "source\(index).sv", context: &context)) }
        let capacity = try RTLResolvedCapacity(signals: 100, expressions: 2000, operands: 4000,
            statements: 1000, children: 2000, caseItems: 100, caseMatches: 200, ports: 20, processes: 100)
        return try SystemVerilogProgramCompiler.compile(trees, top: top, capacity: capacity, maximumNesting: 100, context: &context)
    }
    @Test func hierarchyMatchesCrossSourceParametersAndTypedPortAssignments() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context(1_000_000_000)
        let model = try compile([
            "module p(input [3:0] a,b,output [4:0] y); child #(.W(4)) u(.a(a),.b(b),.y(y)); endmodule",
            "module child #(parameter W=1)(input [W-1:0] a,b,output [W:0] y); assign y=a+b; endmodule"], context: &run)
        #expect(model.portCount == 3)
        for a in 0..<16 { for b in 0..<16 {
            let output = try ProbeRTLProgramEvaluator.evaluate(model, inputs: ["a": a,"b": b], context: &run)
            #expect(output["y"] == a+b)
        } }
    }
    @Test func selectedGenerateAndFrozenIndexesProduceDistinctOccurrences() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context(1_000_000_000)
        let model = try compile(["module p(input [3:0] a,output [3:0] y); if(0) begin: dead missing u(); end else begin: live for(genvar i=0;i<4;i++) begin: g wire x; assign x=a[i]; assign y[i]=x; end end endmodule"], context: &run)
        #expect(model.signalCount == 6)
        for a in 0..<16 { #expect(try ProbeRTLProgramEvaluator.evaluate(model, inputs: ["a": a], context: &run)["y"] == a) }
    }
    @Test func externalLoopBodyWritesAndFinalControlValueArePreserved() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context(1_000_000_000)
        let model = try compile(["module p(input [3:0] a,output logic [3:0] y,output logic [31:0] z); int k; always_comb begin y=0; for(k=0;k<4;k++) begin y[k]=a[k]; k=k+1; end z=k; end endmodule"], context: &run)
        for a in 0..<16 {
            let output = try ProbeRTLProgramEvaluator.evaluate(model, inputs: ["a": a], context: &run)
            #expect(output["y"] == a & 5); #expect(output["z"] == 4)
        }
    }
    @Test func blockingAndNBAOrderingAndCaseCommonContextRemainExplicit() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context(1_000_000_000)
        let model = try compile(["module p(input [3:0] a,output logic [3:0] y,z,output logic c); always_comb begin y=a; z<=y; y=~y; case(4'shf+4'sh0) 8'h0f:c=1; default:c=0; endcase end endmodule"], context: &run)
        for a in 0..<16 {
            let output = try ProbeRTLProgramEvaluator.evaluate(model, inputs: ["a": a], context: &run)
            #expect(output["y"] == (a ^ 15)); #expect(output["z"] == a); #expect(output["c"] == 1)
        }
    }
    @Test func FFClockAndResetRolesDoNotDependOnEventOrder() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for events in ["posedge clk or negedge rst_n", "negedge rst_n or posedge clk"] {
            var run = try context()
            let model = try compile(["module p(input clk,rst_n,en,d,output logic q); always_ff @(\(events)) if(!rst_n) q<=0; else if(en) q<=d; endmodule"], context: &run)
            model.withProgram { (_,_,_,_,_,_,processes) in
                #expect(processes.count == 1)
                guard case .flipFlop(let clock,let edge,let reset?) = processes[0].control else { Issue.record("Missing FF control"); return }
                #expect(edge == .rising); #expect(!reset.activeHigh); #expect(clock != reset.signal)
            }
        }
    }
    @Test func atomicConcatenationSamplesRHSAndAddressesBeforeAnyWrite() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for timing in ["=", "<="] {
            var run = try context(1_000_000_000)
            let model = try compile(["module p(input [3:0] a,output logic [3:0] y); always_comb begin y=a; {y[3:2],y[1:0]}\(timing){y[1:0],y[3:2]}; end endmodule"], context: &run)
            for a in 0..<16 {
                #expect(try ProbeRTLProgramEvaluator.evaluate(model, inputs: ["a": a], context: &run)["y"] == ((a & 3) << 2) | (a >> 2))
            }
        }
        var run = try context(1_000_000_000)
        let model = try compile(["module p(input [3:0] a,output logic [3:0] y,output logic [1:0] i); always_comb begin y=a; i=0; {i,y[i]}=3'b101; end endmodule"], context: &run)
        let overlap = try compile(["module p(output logic [1:0] y); always_comb {y[1:0],y[0]}=3'b110; endmodule"], context: &run)
        for a in 0..<16 {
            let output = try ProbeRTLProgramEvaluator.evaluate(model, inputs: ["a": a], context: &run)
            #expect(output["i"] == 2); #expect(output["y"] == a | 1)
        }
        #expect(try ProbeRTLProgramEvaluator.evaluate(overlap, inputs: [:], context: &run)["y"] == 2)
    }
    @Test func writableSelectionsDiscardInvalidBitsWithoutWrappingNestedDimensions() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context(1_000_000_000)
        let indexed = try compile(["module p(input signed [3:0] i,output logic [3:0] y); always_comb begin y=0; y[i+:2]=2'b11; end endmodule"], context: &run)
        for i in -8..<8 {
            var expected = 0
            for bit in 0..<2 where (0..<4).contains(i+bit) { expected |= 1 << (i+bit) }
            #expect(try ProbeRTLProgramEvaluator.evaluate(indexed, inputs: ["i": i], context: &run)["y"] == expected)
        }
        let nested = try compile(["module p(input [1:0] i,j,output logic [1:0][1:0] y); always_comb begin y=0; y[i][j]=1; end endmodule"], context: &run)
        for i in 0..<4 { for j in 0..<4 {
            #expect(try ProbeRTLProgramEvaluator.evaluate(nested, inputs: ["i": i,"j": j], context: &run)["y"] == (i<2 && j<2 ? 1 << (i*2+j) : 0))
        } }
        let constant = try compile(["module p(output logic [3:0] y); always_comb begin y=0; y[5:2]=4'b1111; y[65'h10000000000000000]=1; end endmodule"], context: &run)
        #expect(try ProbeRTLProgramEvaluator.evaluate(constant, inputs: [:], context: &run)["y"] == 12)
        let wide = try compile(["module p(output logic [9223372036854775807:9223372036854775804] y); always_comb begin y=0; y[65'h8000000000000000-:2]=2'b11; end endmodule"], context: &run)
        #expect(try ProbeRTLProgramEvaluator.evaluate(wide, inputs: [:], context: &run)["y"] == 8)
        let unsigned = try compile(["module p(input i,output logic [3:0] y); always_comb begin y=0; y[i+:2]=2'b11; end endmodule"], context: &run)
        for i in 0..<2 { #expect(try ProbeRTLProgramEvaluator.evaluate(unsigned, inputs: ["i": i], context: &run)["y"] == 3 << i) }
    }
    @Test func partialAndAtomicStaticControlUpdatesReachBodyStepAndExternalSignals() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context(1_000_000_000)
        let partial = try compile(["module p(output logic [3:0] y,output logic [31:0] z); int k; always_comb begin y=0; for(k=0;k<4;k++) begin y[k]=1; k[0]=1; end z=k; end endmodule"], context: &run)
        let atomic = try compile(["module p(output logic [3:0] y,output logic [31:0] z); int k; always_comb begin y=0; for(k=1;k<4;k++) begin y[k]=1; {k[0],k[1]}={k[1],k[0]}; end z=k; end endmodule"], context: &run)
        let a = try ProbeRTLProgramEvaluator.evaluate(partial, inputs: [:], context: &run)
        #expect(a["y"] == 5); #expect(a["z"] == 4)
        let b = try ProbeRTLProgramEvaluator.evaluate(atomic, inputs: [:], context: &run)
        #expect(b["y"] == 10); #expect(b["z"] == 4)
        for body in ["k[0]<=1;", "k[0]=d;", "k[d]=1;"] {
            var failureRun = try context()
            do { _ = try compile(["module p(input d); always_comb for(int k=0;k<2;k++) begin \(body) end endmodule"], context: &failureRun); Issue.record("Nonstatic control update accepted") }
            catch let error as LogicKernelError { guard case .sourceFailure = error else { throw error } }
        }
    }
    @Test func inlineLoopControlDoesNotWriteAShadowedRuntimeSignal() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context(1_000_000_000)
        let model = try compile(["module p(output logic [31:0] y); int k; always_comb begin k=9; for(int k=0;k<3;k++) begin end y=k; end endmodule"], context: &run)
        #expect(try ProbeRTLProgramEvaluator.evaluate(model, inputs: [:], context: &run)["y"] == 9)
    }
    @Test func sourceFailuresRejectRecursiveUnknownAndInconsistentBindings() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        let fixtures = [
            "module p; p u(); endmodule",
            "module p; missing u(); endmodule",
            "module p; endmodule module p; endmodule",
            "module p; child u(); endmodule module child(input a); endmodule",
            "module p(input a); child u(.x(a)); endmodule module child(input b); endmodule",
            "module p(input a); child u(.b(a),.b(a)); endmodule module child(input b); endmodule",
            "module p(input a); child u(.b(a),a); endmodule module child(input b,c); endmodule",
            "module p(input a); child u(1); endmodule module child(output b); assign b=1; endmodule",
            "module p(inout a); endmodule",
            "module p(input a,output y); always_comb y=a; endmodule",
            "module p(input a,output wire logic y); always_comb y=a; endmodule",
            "module p(input clk,rst_n,d,output logic q); always_ff @(posedge clk or posedge rst_n) if(!rst_n) q<=0; else q<=d; endmodule",
            "module p(input a,output logic y); always @(a) y=a; endmodule"]
        for source in fixtures {
            var run = try context()
            do { _ = try compile([source], context: &run); Issue.record("Invalid source accepted: \(source)") }
            catch let error as LogicKernelError {
                guard case .sourceFailure(_, let origin, _) = error else { throw error }
                #expect(origin.byteRange.upperBound <= UInt64(source.utf8.count))
            }
        }
    }
    @Test func proceduralUnrollingCannotTurnVariablesIntoLanguageConstants() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for body in ["localparam M=k; y=M;", "logic [k:0] t; t=0; y=t;",
                     "int m=k; y=m;", "y={k{1'b1}};", "y[0+:k]=0;", "y[k:0]=0;"] {
            var run = try context()
            let source = "module p(output logic [3:0] y); always_comb begin y=0; for(int k=1;k<3;k++) begin \(body) end end endmodule"
            do { _ = try compile([source], context: &run); Issue.record("Procedural variable became a language constant: \(body)") }
            catch let error as LogicKernelError { guard case .sourceFailure = error else { throw error } }
        }
    }
    @Test func programNestingCapacityAndCancellationRemainExplicitFailures() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var setup = try context()
        let tree = try syntax("module p(input a,output y); assign y=a; endmodule", name: "limits.sv", context: &setup)
        let capacity = try RTLResolvedCapacity(signals: 2, expressions: 4, operands: 4, statements: 4,
            children: 4, caseItems: 0, caseMatches: 0, ports: 2, processes: 1)
        var nested = try context()
        do { _ = try SystemVerilogProgramCompiler.compile([tree], top: "p", capacity: capacity, maximumNesting: 1, context: &nested); Issue.record("Program nesting was ignored") }
        catch { guard case .sourceFailure = error else { throw error } }
        let cancellation = LogicCancellationSource(); cancellation.cancel()
        var cancelled = LogicKernelContext(limits: try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
            LogicResource.allCases.map { ($0, UInt64(1_000_000)) })), control: cancellation)
        do { _ = try SystemVerilogProgramCompiler.compile([tree], top: "p", capacity: capacity, maximumNesting: 100, context: &cancelled); Issue.record("Cancelled program was published") }
        catch { #expect(error == .cancelled) }
        var maximums = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) })
        maximums[.managedStorageBytes] = 1
        var limited = LogicKernelContext(limits: try LogicKernelLimits(maximums: maximums), control: LogicCancellationSource())
        do { _ = try SystemVerilogProgramCompiler.compile([tree], top: "p", capacity: capacity, maximumNesting: 100, context: &limited); Issue.record("Storage limit was ignored") }
        catch { guard case .resourceLimit(.managedStorageBytes, _, _) = error else { throw error } }
    }
}
