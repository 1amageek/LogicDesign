import CircuiteFoundation
import LogicIR
import LogicKernelCore
import SystemVerilogFrontend

@available(macOS 26.0, *)
public nonisolated func exerciseProgramElaborationContract() throws {
    let limits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
        LogicResource.allCases.map { ($0, UInt64(100_000_000)) }))
    var run = LogicKernelContext(limits: limits, control: LogicCancellationSource())
    var trees: [SystemVerilogSyntaxTree] = []
    let tree0 = try programSyntax("module p(input [3:0] a,b,output [4:0] y); child #(.W(4)) u(.a(a),.b(b),.y(y)); endmodule", digest: "77c3a75149c88cded71a32976395c9ca49ec084a18e809e60b3773e14df3d812", context: &run)
    let tree1 = try programSyntax("module child #(parameter W=1)(input [W-1:0] a,b,output [W:0] y); assign y=a+b; endmodule", digest: "48a62a2a3e2fd898afc940513edca45c3a9322ac24726b37f26e97790c82dfa4", context: &run)
    let tree2 = try programSyntax("module p(input [3:0] a,output logic [3:0] y,output logic [1:0] i,output logic [31:0] z); int k; always_comb begin y=a; i=0; {i,y[i]}=3'b101; for(k=0;k<4;k++) begin k[0]=1; end for(int k=0;k<3;k++) begin end z=k; end endmodule", digest: "4f475be949cbdd8f24b38cd548b663a79018ffd210546f38df6d1689cf26a8f4", context: &run)
    let tree3 = try programSyntax("module p(input [1:0] i,j,output logic [1:0][1:0] y); always_comb begin y=0; y[i][j]=1; end endmodule", digest: "b4c7f702a60a27fda6ef538efa5a881371fb242d1d4cd1b62dc258c07194b2a5", context: &run)
    trees.append(tree0); trees.append(tree1)
    let capacity = try RTLResolvedCapacity(signals: 100, expressions: 2000, operands: 4000,
        statements: 1000, children: 2000, caseItems: 100, caseMatches: 200, ports: 20, processes: 100)
    let hierarchy = try SystemVerilogProgramCompiler.compile(trees, top: "p", capacity: capacity, maximumNesting: 100, context: &run)
    for a in 0..<16 { for b in 0..<16 {
        let output = try ProbeRTLProgramEvaluator.evaluate(hierarchy, inputs: ["a": a, "b": b], context: &run)
        precondition(output["y"] == a+b)
    } }
    let atomic = try SystemVerilogProgramCompiler.compile([tree2], top: "p", capacity: capacity, maximumNesting: 100, context: &run)
    for a in 0..<16 {
        let output = try ProbeRTLProgramEvaluator.evaluate(atomic, inputs: ["a": a], context: &run)
        precondition(output["y"] == a | 1 && output["i"] == 2 && output["z"] == 4)
    }
    let deepTree = try programSyntax("module p(input a,output logic y); always_comb begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin begin y=a; end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end end endmodule", digest: "4e3335c5d4083e64bc2d34194f24c9672e6bff1eb8f54681c953a54a56eb1365", context: &run)
    let deep = try SystemVerilogProgramCompiler.compile([deepTree], top: "p", capacity: capacity, maximumNesting: 100, context: &run)
    let deepOutput = try ProbeRTLProgramEvaluator.evaluate(deep, inputs: ["a": 1], context: &run)
    precondition(deepOutput["y"] == 1)
    do throws(LogicKernelError) {
        _ = try SystemVerilogProgramCompiler.compile([deepTree], top: "p", capacity: capacity, maximumNesting: 20, context: &run)
        throw .invalidModel("Deep source bypassed the selected nesting limit")
    } catch {
        guard case .sourceFailure = error else { throw error }
    }
    let dynamic = try SystemVerilogProgramCompiler.compile([tree3], top: "p", capacity: capacity, maximumNesting: 100, context: &run)
    for i in 0..<4 { for j in 0..<4 {
        let output = try ProbeRTLProgramEvaluator.evaluate(dynamic, inputs: ["i": i, "j": j], context: &run)
        precondition(output["y"] == (i<2 && j<2 ? 1 << (i*2+j) : 0))
    } }
}

@available(macOS 26.0, *)
private nonisolated func programSyntax(_ text: String, digest: String, context: inout LogicKernelContext)
    throws(LogicKernelError) -> SystemVerilogSyntaxTree {
    let bytes = Array(text.utf8)
    let artifact: ArtifactID
    do { artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256, hexadecimalValue: digest), byteCount: UInt64(bytes.count)) }
    catch { throw .invalidModel("Invalid program fixture identity") }
    let source = try LogicSourceDocument(logicalName: "program.sv", artifactID: artifact, bytes: bytes, context: &context)
    let tokens = try SystemVerilogByteLexer().tokenize(source, maximumTokens: bytes.count+1, context: &context)
    return try SystemVerilogSyntaxParser.parse(tokens, limits: SystemVerilogSyntaxLimits(nodes: bytes.count,
        children: bytes.count, symbols: bytes.count, nesting: 100), context: &context)
}
