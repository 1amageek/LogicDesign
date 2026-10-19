import CircuiteFoundation
import LogicIR
import LogicKernelCore
import SystemVerilogFrontend

@available(macOS 26.0, *)
public nonisolated func exerciseParameterOverrideContract() throws {
    let limits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
        LogicResource.allCases.map { ($0, UInt64(2_000_000)) }))
    var context = LogicKernelContext(limits: limits, control: LogicCancellationSource())
    let text = "module child #(parameter [8:0] A=0, parameter W=2); parameter [W-1:0] MASK='1; endmodule module p; parameter A=8'hff; child #(.W(4'd9),.A(A+8'd1)) u(); child #(A+8'd1,4'd9) v(); child #(.MASK(1)) bad(); endmodule"
    let artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
        hexadecimalValue: "a38ef360e5fb91a90b5a0cab49d18f4543e0dabc26fbeecf96573a88aa8f67c3"), byteCount: 212)
    let source = try LogicSourceDocument(logicalName: "overrides.sv", artifactID: artifact, bytes: Array(text.utf8), context: &context)
    let tokens = try SystemVerilogByteLexer().tokenize(source, maximumTokens: 180, context: &context)
    let syntax = try SystemVerilogSyntaxParser.parse(tokens, limits: SystemVerilogSyntaxLimits(
        nodes: 180, children: 180, symbols: 30, nesting: 30), context: &context)
    let child = try SystemVerilogParameterBinder.bind(syntax, module: syntax.child(at: syntax.modules.lowerBound), context: &context)
    let parentBindings = try SystemVerilogParameterBinder.bind(syntax, module: syntax.child(at: syntax.modules.upperBound - 1), context: &context)
    let parent = try SystemVerilogConstantEvaluator.evaluate(parentBindings, context: &context)
    var count = 0
    var firstInstance: Int?
    for node in 0..<syntax.nodeCount {
        guard case .instance = try syntax.node(at: node).kind else { continue }
        if firstInstance == nil { firstInstance = node }
        count += 1
        if count <= 2 {
            let result = try SystemVerilogInstanceParameterResolver.evaluate(instance: node, in: parent, child: child, context: &context)
            let sum = try result.value(forDeclaration: child.declaration(at: 0))
            let mask = try result.value(forDeclaration: child.declaration(at: 2))
            let sumValue = try sum.value.binaryInt(signed: false, context: &context)
            let maskValue = try mask.value.binaryInt(signed: false, context: &context)
            precondition(sum.type.width.value == 9 && sumValue == 256 && sum.origin.artifactID == artifact)
            precondition(mask.type.width.value == 9 && maskValue == 511)
        } else {
            do {
                _ = try SystemVerilogInstanceParameterResolver.evaluate(instance: node, in: parent, child: child, context: &context)
                preconditionFailure("An implicitly local body parameter was overridden")
            } catch {
                guard case .sourceFailure(let code, let range, _) = error else { throw error }
                precondition(code.rawValue == "SV_PARAMETER_LOCAL_OVERRIDE" && range.artifactID == artifact && range.byteRange == 186..<194)
            }
        }
    }
    precondition(count == 3)
    guard let firstInstance else { throw LogicKernelError.invalidModel("Expected parameter probe instance") }
    let control = LogicCancellationSource(); control.cancel()
    var cancelled = LogicKernelContext(limits: limits, control: control)
    do {
        _ = try SystemVerilogInstanceParameterResolver.evaluate(instance: firstInstance, in: parent, child: child, context: &cancelled)
        preconditionFailure("Cancelled instance parameters were published")
    } catch {
        guard case .cancelled = error else { throw error }
        precondition(cancelled.usage[.allocationBytes] == 0)
    }
    let tight = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
        LogicResource.allCases.map { ($0, UInt64(1)) }))
    var exhausted = LogicKernelContext(limits: tight, control: LogicCancellationSource())
    do {
        _ = try SystemVerilogInstanceParameterResolver.evaluate(instance: firstInstance, in: parent, child: child, context: &exhausted)
        preconditionFailure("Instance parameter storage exceeded admission")
    } catch {
        guard case .resourceLimit(.managedStorageBytes, _, _) = error else { throw error }
        precondition(exhausted.usage[.allocationBytes] == 0)
    }
}
