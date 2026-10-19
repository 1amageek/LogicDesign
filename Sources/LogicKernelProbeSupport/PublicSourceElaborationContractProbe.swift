import CircuiteFoundation
import LogicIR
import LogicKernelCore
import SystemVerilogFrontend

@available(macOS 26.0, *)
public nonisolated func exercisePublicSourceElaborationContract() throws(LogicKernelError) {
    let limits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
        LogicResource.allCases.map { ($0, UInt64(100_000_000)) }))
    var context = LogicKernelContext(limits: limits, control: LogicCancellationSource())
    var documents: [LogicSourceDocument] = []
    do {
        let bytes = Array("`define W 4\nmodule p(input [`W-1:0] a,b,output [`W:0] y);".utf8)
        let artifact: ArtifactID
        do { artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
            hexadecimalValue: "daa4aa18c111cb3510569377b9da7df346582a520ea390e733426fce8bc64781"), byteCount: UInt64(bytes.count)) }
        catch { throw .invalidModel("Public elaboration fixture identity is invalid") }
        documents.append(try LogicSourceDocument(logicalName: "start.sv", artifactID: artifact, bytes: bytes, context: &context))
    }
    do {
        let bytes = Array("child #(.W(`W)) u(.a(a),.b(b),.y(y));endmodule\n`include \"child.svh\"".utf8)
        let artifact: ArtifactID
        do { artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
            hexadecimalValue: "63d3e2458f4e529c866ea9be089acc7671677e1fa9bfdc8862acd294c0ebcbfb"), byteCount: UInt64(bytes.count)) }
        catch { throw .invalidModel("Public elaboration fixture identity is invalid") }
        documents.append(try LogicSourceDocument(logicalName: "end.sv", artifactID: artifact, bytes: bytes, context: &context))
    }
    do {
        let bytes = Array("module child #(parameter W=1)(input [W-1:0] a,b,output [W:0] y);assign y=a+b;endmodule".utf8)
        let artifact: ArtifactID
        do { artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
            hexadecimalValue: "478560ca5acdc48502660397a6b1a165871ee410264489921345cfd4c41a9a0c"), byteCount: UInt64(bytes.count)) }
        catch { throw .invalidModel("Public elaboration fixture identity is invalid") }
        documents.append(try LogicSourceDocument(logicalName: "child.svh", artifactID: artifact, bytes: bytes, context: &context))
    }
    do {
        let bytes = Array("module bad(output y);assign y=1'bx;endmodule".utf8)
        let artifact: ArtifactID
        do { artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
            hexadecimalValue: "90721267eec53c6ea203a377c41f6c2e45d1f25fa95bc76a17e27c7060969ebc"), byteCount: UInt64(bytes.count)) }
        catch { throw .invalidModel("Public elaboration fixture identity is invalid") }
        documents.append(try LogicSourceDocument(logicalName: "bad.sv", artifactID: artifact, bytes: bytes, context: &context))
    }
    let badArtifact = documents[3].artifactID
    let bundle = try LogicSourceBundle(documents: documents, context: &context)
    let capacity = try RTLResolvedCapacity(signals: 100, expressions: 2000, operands: 4000, statements: 1000,
        children: 2000, caseItems: 100, caseMatches: 200, ports: 20, processes: 100)
    let syntax = try SystemVerilogSyntaxLimits(nodes: 2000, children: 4000, symbols: 1000, nesting: 60)
    let options = try SystemVerilogElaborationOptions(roots: ["start.sv", "end.sv"], top: "p", maximumTokens: 2000,
        syntax: syntax, rtl: capacity, maximumNesting: 60)
    let engine: any SystemVerilogElaborating = NativeSystemVerilogElaborator()
    let model = try engine.elaborate(bundle, options: options, context: &context)
    for a in 0..<16 { for b in 0..<16 {
        guard try ProbeRTLProgramEvaluator.evaluate(model, inputs: ["a": a, "b": b], context: &context)["y"] == a+b else {
            throw .invalidModel("Public elaboration changed the circuit output")
        }
    } }
    let badOptions = try SystemVerilogElaborationOptions(roots: ["bad.sv"], top: "bad", maximumTokens: 2000,
        syntax: syntax, rtl: capacity, maximumNesting: 60)
    do throws(LogicKernelError) {
        _ = try engine.elaborate(bundle, options: badOptions, context: &context)
        throw .invalidModel("Public elaboration accepted synthesis X")
    } catch {
        guard case .sourceFailure(let code, let origin, _) = error,
              code.rawValue == "SV_SYNTHESIS_XZ_LITERAL", origin.artifactID == badArtifact else { throw error }
    }
    let cancellation = LogicCancellationSource(); cancellation.cancel()
    var cancelled = LogicKernelContext(limits: limits, control: cancellation)
    do throws(LogicKernelError) {
        _ = try engine.elaborate(bundle, options: options, context: &cancelled)
        throw .invalidModel("Public elaboration accepted cancellation")
    } catch { guard error == .cancelled else { throw error } }
}
