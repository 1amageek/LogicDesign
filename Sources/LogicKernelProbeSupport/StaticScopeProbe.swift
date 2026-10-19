import CircuiteFoundation
import LogicIR
import LogicKernelCore
import SystemVerilogFrontend

@available(macOS 26.0, *)
public nonisolated func exerciseStaticScopeContract() throws {
    let limits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
        LogicResource.allCases.map { ($0, UInt64(4_000_000)) }))
    var context = LogicKernelContext(limits: limits, control: LogicCancellationSource())
    let text = "module child #(parameter [8:0] A=0); endmodule module p; parameter A=7; for(genvar i=0;i<3;i++) begin: g localparam [7:0] A=8'hff-i; child #(A+8'd1) u(); end if(0) begin: bad logic A; child #(A) bad_instance(); end endmodule"
    let artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
        hexadecimalValue: "18f39043fbee59bb7abfc73b222a375fd5124dcd63b9d3317aa2de6160debd23"), byteCount: 224)
    let source = try LogicSourceDocument(logicalName: "static-scopes.sv", artifactID: artifact,
        bytes: Array(text.utf8), context: &context)
    let tokens = try SystemVerilogByteLexer().tokenize(source, maximumTokens: 220, context: &context)
    let syntax = try SystemVerilogSyntaxParser.parse(tokens, limits: SystemVerilogSyntaxLimits(
        nodes: 220, children: 220, symbols: 50, nesting: 40), context: &context)
    let child = try SystemVerilogParameterBinder.bind(syntax, module: syntax.child(at: syntax.modules.lowerBound), context: &context)
    let bindings = try SystemVerilogParameterBinder.bind(syntax, module: syntax.child(at: syntax.modules.upperBound-1), context: &context)
    let defaults = try SystemVerilogConstantEvaluator.evaluate(bindings, context: &context)
    let root = try SystemVerilogConstantScope.module(defaults, context: &context)
    var retained: SystemVerilogConstantExpression?
    var loopCount = 0
    for node in 0..<syntax.nodeCount {
        guard case .generateFor(_, _, _, let body) = try syntax.node(at: node).kind else { continue }
        loopCount += 1
        let instance = try scopeProbeInstance(in: syntax, container: body, context: &context)
        let rootOwns = try root.owns(instance, context: &context)
        precondition(!rootOwns)
        for index in 0..<3 {
            let value = try LogicFourStateVector(width: LogicBitWidth(32), valueWords: [UInt64(index)], unknownWords: [0])
            let iteration = try root.iteration(of: node, value: value, context: &context)
            let selected = try iteration.entering(body, context: &context)
            let result = try SystemVerilogInstanceParameterResolver.evaluate(instance: instance, in: selected, child: child, context: &context)
            let constant = try result.value(forDeclaration: child.declaration(at: 0))
            let integer = try constant.value.binaryInt(signed: false, context: &context)
            precondition(integer == 256-index && constant.type.width.value == 9 && constant.origin.artifactID == artifact)
            if index == 0 {
                guard case .instance(_, _, let assignments, _) = try syntax.node(at: instance).kind,
                      case .binding(_, let expression?) = try syntax.node(at: syntax.child(at: assignments.lowerBound)).kind else {
                    throw LogicKernelError.invalidModel("Probe instance lacks a constant argument")
                }
                retained = try SystemVerilogConstantExpression.prepare(node: expression, in: selected, context: &context)
            }
        }
    }
    precondition(loopCount == 1)
    guard let retained else { throw LogicKernelError.invalidModel("Probe lost its retained iteration expression") }
    let retainedValue = try retained.evaluate(width: 9, context: &context).binaryInt(signed: false, context: &context)
    precondition(retainedValue == 256)
    for node in 0..<syntax.nodeCount {
        guard case .generateIf(_, let body, _) = try syntax.node(at: node).kind else { continue }
        let selected = try root.entering(body, context: &context)
        let instance = try scopeProbeInstance(in: syntax, container: body, context: &context)
        do {
            _ = try SystemVerilogInstanceParameterResolver.evaluate(instance: instance, in: selected, child: child, context: &context)
            preconditionFailure("Runtime name fell back to an outer parameter")
        } catch {
            guard case .sourceFailure(let code, let range, _) = error else { throw error }
            precondition(code.rawValue == "SV_SCOPE_NONCONSTANT_NAME" && range.artifactID == artifact)
        }
        let control = LogicCancellationSource(); control.cancel()
        var cancelled = LogicKernelContext(limits: limits, control: control)
        do {
            _ = try root.entering(body, context: &cancelled)
            preconditionFailure("Cancelled lexical scope was published")
        } catch {
            guard case .cancelled = error else { throw error }
            precondition(cancelled.usage[.allocationBytes] == 0)
        }
    }
    try exerciseDirectConditionalScope(context: &context)
    let tight = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
        LogicResource.allCases.map { ($0, UInt64(1)) }))
    var exhausted = LogicKernelContext(limits: tight, control: LogicCancellationSource())
    do {
        _ = try SystemVerilogConstantScope.module(defaults, context: &exhausted)
        preconditionFailure("Scope payload exceeded its admission")
    } catch {
        guard case .resourceLimit(.managedStorageBytes, _, _) = error else { throw error }
        precondition(exhausted.usage[.allocationBytes] == 0)
    }
}

@available(macOS 26.0, *)
private nonisolated func scopeProbeInstance(in syntax: borrowing SystemVerilogSyntaxTree,
    container: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
    let boundary = try syntax.node(at: container).byteRange
    for node in 0..<container {
        try context.charge(.workUnits)
        let value = try syntax.node(at: node)
        if case .instance = value.kind,
           value.byteRange.lowerBound >= boundary.lowerBound && value.byteRange.upperBound <= boundary.upperBound { return node }
    }
    throw LogicKernelError.invalidModel("Probe scope lacks an instance")
}

@available(macOS 26.0, *)
private nonisolated func exerciseDirectConditionalScope(context: inout LogicKernelContext) throws {
    let text = "module p; parameter A=7; if(1) case(A) 7: if(1) begin: g child #(A) u(); end else begin: g child #(A+1) v(); end default: begin: g child #(A+2) w(); end endcase endmodule"
    let artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
        hexadecimalValue: "26846336c6e779ee0265a0049b2ccd445ca65ef70b540f9b4b41aee3ee76bb05"), byteCount: 170)
    let source = try LogicSourceDocument(logicalName: "direct-nesting.sv", artifactID: artifact,
        bytes: Array(text.utf8), context: &context)
    let tokens = try SystemVerilogByteLexer().tokenize(source, maximumTokens: 200, context: &context)
    let syntax = try SystemVerilogSyntaxParser.parse(tokens, limits: SystemVerilogSyntaxLimits(
        nodes: 200, children: 200, symbols: 40, nesting: 40), context: &context)
    let bindings = try SystemVerilogParameterBinder.bind(syntax, module: syntax.child(at: syntax.modules.lowerBound), context: &context)
    let defaults = try SystemVerilogConstantEvaluator.evaluate(bindings, context: &context)
    let root = try SystemVerilogConstantScope.module(defaults, context: &context)
    var branches = 0
    for node in 0..<syntax.nodeCount {
        switch try syntax.node(at: node).kind {
        case .generateIf(let condition, _, _), .generateCase(let condition, _):
            let owned = try root.owns(condition, context: &context)
            precondition(owned)
            _ = try SystemVerilogConstantExpression.prepare(node: condition, in: defaults, context: &context)
        case .generateBlock:
            let branch = try root.entering(node, context: &context)
            let instance = try scopeProbeInstance(in: syntax, container: node, context: &context)
            guard case .instance(_, _, let assignments, _) = try syntax.node(at: instance).kind,
                  case .binding(_, let expression?) = try syntax.node(at: syntax.child(at: assignments.lowerBound)).kind else {
                throw LogicKernelError.invalidModel("Direct nesting probe lacks its instance argument")
            }
            let handle = try SystemVerilogConstantExpression.prepare(node: expression, in: branch, context: &context)
            let value = try handle.evaluate(width: 32, context: &context).binaryInt(signed: false, context: &context)
            precondition(value == 7 + branches)
            branches += 1
        default: break
        }
    }
    precondition(branches == 3)
}
