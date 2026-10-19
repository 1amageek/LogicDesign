import CircuiteFoundation
import LogicIR
import LogicKernelCore
import SystemVerilogFrontend

@available(macOS 26.0, *)
public nonisolated func exerciseConstantEvaluationContract() throws {
    let limits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
        LogicResource.allCases.map { ($0, UInt64(2_000_000)) }))
    var context = LogicKernelContext(limits: limits, control: LogicCancellationSource())
    let text = "module m; parameter [8:0] SUM=8'hff+8'h01; parameter signed [7:0] S=-4'sd1; parameter [15:0] MIX=S+8'd0; parameter [256:0] W='1; parameter [256:0] ZERO=W+257'd1; parameter [0:7] A=8'hb2; parameter B=A[2 +: 3]; parameter C={2'b10,{0{1'b1}},2'b01}; endmodule"
    let artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
        hexadecimalValue: "9d83b3d8f77d6249332602c9dc95fbd42ce260dc888662f820ce858a2880616f"), byteCount: 256)
    let source = try LogicSourceDocument(logicalName: "constants.sv", artifactID: artifact, bytes: Array(text.utf8), context: &context)
    let tokens = try SystemVerilogByteLexer().tokenize(source, maximumTokens: 150, context: &context)
    let tree = try SystemVerilogSyntaxParser.parse(tokens, limits: SystemVerilogSyntaxLimits(
        nodes: 150, children: 150, symbols: 30, nesting: 30), context: &context)
    let bindings = try SystemVerilogParameterBinder.bind(tree, module: tree.child(at: tree.modules.lowerBound), context: &context)
    let defaults = try SystemVerilogConstantEvaluator.evaluate(bindings, context: &context)
    for (ordinal, width, signed, expected) in [(0,9,false,256),(1,8,true,-1),(2,16,false,255),(6,3,false,6),(7,4,false,9)] {
        let value = try defaults.value(forDeclaration: bindings.declaration(at: ordinal))
        precondition(value.type.width.value == width && value.type.isSigned == signed)
        let integer = try value.value.binaryInt(signed: signed, context: &context)
        precondition(integer == expected)
    }
    let wide = try defaults.value(forDeclaration: bindings.declaration(at: 3))
    let zero = try defaults.value(forDeclaration: bindings.declaration(at: 4))
    precondition(wide.type.width.value == 257 && zero.type.width.value == 257)
    for bit in 0..<257 {
        let one = try wide.value.bit(at: bit); let cleared = try zero.value.bit(at: bit)
        precondition(one == .one && cleared == .zero)
    }
    let retained = defaults.withValues { values in
        var count = 0
        for index in values.indices { if values[index] != nil { count += 1 } }
        return count == 8
    }
    precondition(retained)
    let rejectedText = "module m; parameter [7:0] A=0; parameter B=A[8]; endmodule"
    let rejectedArtifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
        hexadecimalValue: "c5da57a99838662274de87e746ca20537642724f9fc778e52c5002e936382c9f"), byteCount: 58)
    let rejected = try LogicSourceDocument(logicalName: "invalid-constant.sv", artifactID: rejectedArtifact,
        bytes: Array(rejectedText.utf8), context: &context)
    let rejectedTokens = try SystemVerilogByteLexer().tokenize(rejected, maximumTokens: 40, context: &context)
    let rejectedTree = try SystemVerilogSyntaxParser.parse(rejectedTokens, limits: SystemVerilogSyntaxLimits(
        nodes: 50, children: 50, symbols: 10, nesting: 20), context: &context)
    let rejectedBindings = try SystemVerilogParameterBinder.bind(rejectedTree,
        module: rejectedTree.child(at: rejectedTree.modules.lowerBound), context: &context)
    do {
        _ = try SystemVerilogConstantEvaluator.evaluate(rejectedBindings, context: &context)
        preconditionFailure("Out-of-range constant selection was admitted")
    } catch {
        guard case .sourceFailure(let code, let source, _) = error else { throw error }
        precondition(code.rawValue == "SV_SYNTHESIS_SELECT_X" && source.artifactID == rejectedArtifact && source.byteRange == 43..<47)
    }
    let cancellation = LogicCancellationSource(); cancellation.cancel()
    var cancelled = LogicKernelContext(limits: limits, control: cancellation)
    do {
        _ = try SystemVerilogConstantEvaluator.evaluate(bindings, context: &cancelled)
        preconditionFailure("Cancelled constants were published")
    } catch {
        guard case .cancelled = error else { throw error }
        precondition(cancelled.usage[.allocationBytes] == 0)
    }
    let tight = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
        LogicResource.allCases.map { ($0, UInt64(1)) }))
    var exhausted = LogicKernelContext(limits: tight, control: LogicCancellationSource())
    do {
        _ = try SystemVerilogConstantEvaluator.evaluate(bindings, context: &exhausted)
        preconditionFailure("Constant storage exceeded admission")
    } catch {
        guard case .resourceLimit(.managedStorageBytes, _, _) = error else { throw error }
        precondition(exhausted.usage[.allocationBytes] == 0)
    }
}
