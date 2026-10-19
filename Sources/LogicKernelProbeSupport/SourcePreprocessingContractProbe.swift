import CircuiteFoundation
import LogicIR
import LogicKernelCore
import SystemVerilogFrontend

@available(macOS 26.0, *)
package nonisolated func exerciseSourcePreprocessingContract() throws(LogicKernelError) {
    var context = LogicKernelContext(limits: try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
        LogicResource.allCases.map { ($0, UInt64(100_000_000)) })), control: LogicCancellationSource())
    try sourcePreprocessingContractProbe(context: &context)
}

@available(macOS 26.0, *)
package nonisolated func sourcePreprocessingContractProbe(context: inout LogicKernelContext) throws(LogicKernelError) {
    var documents: [LogicSourceDocument] = []
    do {
        let bytes = Array("`define BOOL(x) ((x)^1'b1)\n`include \"defs.svh\"\n`ifdef ENABLE\nmodule p(input a,output y);assign y=`APPLY(a);endmodule\n`else\ninvalid source `MISSING\n`endif\n".utf8)
        let artifact: ArtifactID
        do { artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
            hexadecimalValue: "5cb85740e95cd9704f22f50961340ee46828b88cc95945f76c6a0c56408dde51"), byteCount: UInt64(bytes.count)) }
        catch { throw .invalidModel("Preprocessing fixture identity is invalid") }
        documents.append(try LogicSourceDocument(logicalName: "root.sv", artifactID: artifact, bytes: bytes, context: &context))
    }
    do {
        let bytes = Array("`define ENABLE\n`define APPLY `BOOL\n".utf8)
        let artifact: ArtifactID
        do { artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
            hexadecimalValue: "bc75ce33068a8bdf97f904deec60f147de847e193f7feae5c09b0831851a67f2"), byteCount: UInt64(bytes.count)) }
        catch { throw .invalidModel("Preprocessing fixture identity is invalid") }
        documents.append(try LogicSourceDocument(logicalName: "defs.svh", artifactID: artifact, bytes: bytes, context: &context))
    }
    do {
        let bytes = Array("`define R `R\n`R".utf8)
        let artifact: ArtifactID
        do { artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
            hexadecimalValue: "aa7ce4a27bc1045ee77eaf5dd46baeec3f96e0184f0749afaa9ce534ae5c3802"), byteCount: UInt64(bytes.count)) }
        catch { throw .invalidModel("Preprocessing refusal fixture identity is invalid") }
        documents.append(try LogicSourceDocument(logicalName: "cycle.sv", artifactID: artifact, bytes: bytes, context: &context))
    }
    let cycleArtifact = documents[2].artifactID
    let bundle = try LogicSourceBundle(documents: documents, context: &context)
    let texts = try SystemVerilogSourcePreprocessor.preprocess(bundle, roots: ["root.sv"], maximumNesting: 40, context: &context)
    let text = texts[0]
    let tokens = try SystemVerilogByteLexer().tokenize(text, maximumTokens: text.byteCount + 1, context: &context)
    let tree = try SystemVerilogSyntaxParser.parse(tokens, limits: SystemVerilogSyntaxLimits(
        nodes: text.byteCount + 1, children: text.byteCount + 1, symbols: text.byteCount + 1, nesting: 40), context: &context)
    let model = try SystemVerilogProgramCompiler.compile([tree], top: "p", capacity: RTLResolvedCapacity(
        signals: 16, expressions: 128, operands: 256, statements: 64, children: 128,
        caseItems: 16, caseMatches: 32, ports: 16, processes: 16), maximumNesting: 40, context: &context)
    for value in 0..<2 {
        guard try ProbeRTLProgramEvaluator.evaluate(model, inputs: ["a": value], context: &context)["y"] == value ^ 1 else {
            throw .invalidModel("Preprocessed source changed circuit behavior")
        }
    }
    let root = try bundle.document(at: 0)
    let found = model.withExpressions { expressions, _, _ in
        for expression in expressions.indices {
            if expressions[expression].origin?.artifactID == root.artifactID,
               expressions[expression].origin?.byteRange == 97..<106 { return true }
        }
        return false
    }
    guard found else { throw .invalidModel("Macro expansion lost its invocation origin") }
    do throws(LogicKernelError) {
        _ = try SystemVerilogSourcePreprocessor.preprocess(bundle, roots: ["cycle.sv"], maximumNesting: 40, context: &context)
        throw .invalidModel("Recursive macro was accepted")
    } catch {
        guard case .sourceFailure(let code, let origin, _) = error,
              code.rawValue == "SV_PP_MACRO_CYCLE", origin.artifactID == cycleArtifact,
              origin.byteRange == 13..<15 else { throw error }
    }
    let control = LogicCancellationSource(); control.cancel()
    var cancelled = LogicKernelContext(limits: try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
        LogicResource.allCases.map { ($0, UInt64(100_000_000)) })), control: control)
    do throws(LogicKernelError) {
        _ = try SystemVerilogSourcePreprocessor.preprocess(bundle, roots: ["root.sv"], maximumNesting: 40, context: &cancelled)
        throw .invalidModel("Cancelled preprocessing published success")
    } catch { guard error == .cancelled else { throw error } }
}
