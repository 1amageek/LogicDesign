import CircuiteFoundation
import LogicIR
import LogicKernelCore
import SystemVerilogFrontend

@available(macOS 26.0, *)
package nonisolated func exerciseSourceTextContract() throws(LogicKernelError) {
    let limits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
        LogicResource.allCases.map { ($0, UInt64(100_000_000)) }))
    var context = LogicKernelContext(limits: limits, control: LogicCancellationSource())
    try sourceTextContractProbe(context: &context)
}

@available(macOS 26.0, *)
package nonisolated func sourceTextContractProbe(context: inout LogicKernelContext) throws(LogicKernelError) {
    let bytes = Array("`EXPAND".utf8)
    let artifact: ArtifactID
    do {
        artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
            hexadecimalValue: "555dcfd3717302e5bc2e6dac46056211b97394f52b6a143705a77ab1c50b3d8f"), byteCount: 7)
    } catch { throw .invalidModel("Source text fixture identity is invalid") }
    let root = try LogicSourceDocument(logicalName: "root.sv", artifactID: artifact, bytes: bytes, context: &context)
    let anchor = try LogicKernelSourceRange(artifactID: artifact, byteRange: 0..<7)
    let eof = try LogicKernelSourceRange(artifactID: artifact, byteRange: 7..<7)
    do throws(LogicKernelError) {
        _ = try SystemVerilogSourceText(root: root, bytes: [65], segments: [
            SystemVerilogSourceSegment(textRange: 0..<1, document: root,
                origin: LogicKernelSourceRange(artifactID: artifact, byteRange: 0..<1), isExact: true)
        ], terminalOrigin: eof, context: &context)
        throw .invalidModel("Incorrect bytes claimed exact source correspondence")
    } catch {
        guard error == .invalidInput("Exact source segment differs from its input artifact bytes") else { throw error }
    }
    for stage in 0..<4 {
        let expanded: String
        switch stage {
        case 0: expanded = "module p(input logic a,output logic y);always_comb y=a;endmodule"
        case 1: expanded = "\0"
        case 2: expanded = "module p(;"
        default: expanded = "module p(output logic y);assign y=1'bx;endmodule"
        }
        let textBytes = Array(expanded.utf8)
        let text = try SystemVerilogSourceText(root: root, bytes: textBytes, segments: [
            SystemVerilogSourceSegment(textRange: 0..<textBytes.count, document: root, origin: anchor, isExact: false)
        ], terminalOrigin: eof, context: &context)
        var phase = 1
        do throws(LogicKernelError) {
            let tokens = try SystemVerilogByteLexer().tokenize(text, maximumTokens: text.byteCount + 1, context: &context)
            phase = 2
            let tree = try SystemVerilogSyntaxParser.parse(tokens, limits: SystemVerilogSyntaxLimits(
                nodes: text.byteCount + 1, children: text.byteCount + 1, symbols: text.byteCount + 1,
                nesting: 40), context: &context)
            phase = 3
            let rtl = try SystemVerilogProgramCompiler.compile([tree], top: "p", capacity: RTLResolvedCapacity(
                signals: 16, expressions: 128, operands: 256, statements: 64, children: 128,
                caseItems: 16, caseMatches: 32, ports: 16, processes: 16), maximumNesting: 40, context: &context)
            guard stage == 0 else { throw .invalidModel("Invalid transformed source was accepted") }
            for value in 0..<2 {
                let output = try ProbeRTLProgramEvaluator.evaluate(rtl, inputs: ["a": value], context: &context)
                guard output["y"] == value else { throw .invalidModel("Transformed source changed procedural behavior") }
            }
            let valid = rtl.withExpressions { expressions, _, _ in
                for index in expressions.indices where expressions[index].origin != anchor { return false }
                return !expressions.isEmpty
            }
            guard valid else { throw .invalidModel("Transformed expression origin is not its exact expansion site") }
        } catch {
            guard stage != 0, phase == stage, case .sourceFailure(let code, let location, _) = error,
                  location == anchor else { throw error }
            if stage == 1, code.rawValue != "SV_LEX_INVALID_CHARACTER" { throw error }
            if stage == 3, code.rawValue != "SV_SYNTHESIS_XZ_LITERAL" { throw error }
        }
    }
}
