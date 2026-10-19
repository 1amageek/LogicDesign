import CircuiteFoundation
import LogicIR
import LogicKernelCore
import SystemVerilogFrontend

@available(macOS 26.0, *)
public nonisolated func exerciseStaticControlContract() throws {
    let limits = try LogicKernelLimits(maximums:Dictionary(uniqueKeysWithValues:LogicResource.allCases.map {($0,UInt64(4_000_000))}))
    var context = LogicKernelContext(limits:limits,control:LogicCancellationSource())
    let text = "module p; genvar i; for(i=-1;i<2;i++) begin: g localparam A=i; end case(4'shf+4'sh0) 8'h0f: begin: yes end 8'h00: begin: no end endcase endmodule"
    let artifact = try ArtifactID(digest:ContentDigest(algorithm:.sha256,hexadecimalValue:"5ed80e3ae62529725e3f79564e82245fe5113357a35ca8e168a565e4f81cd11d"),byteCount:145)
    let source = try LogicSourceDocument(logicalName:"static-control.sv",artifactID:artifact,bytes:Array(text.utf8),context:&context)
    let tokens = try SystemVerilogByteLexer().tokenize(source,maximumTokens:200,context:&context)
    let syntax = try SystemVerilogSyntaxParser.parse(tokens,limits:SystemVerilogSyntaxLimits(nodes:200,children:200,symbols:40,nesting:40),context:&context)
    let defaults = try SystemVerilogConstantEvaluator.evaluate(SystemVerilogParameterBinder.bind(syntax,module:syntax.child(at:syntax.modules.lowerBound),context:&context),context:&context)
    let root = try SystemVerilogConstantScope.module(defaults,context:&context)
    var selected: Int?; var yes: Int?; var iterations = 0
    for node in 0..<syntax.nodeCount {
        switch try syntax.node(at:node).kind {
        case .generateBlock(let label?,_):
            let range = try syntax.symbolRange(at:label)
            if syntax.source.withBytes({$0[range.lowerBound] == 121}) {yes = node}
        case .generateCase:
            selected = try SystemVerilogGenerateSelector.select(node,in:root,context:&context)
        case .generateFor:
            var control = try SystemVerilogStaticLoop.prepare(node,in:root,context:&context)
            var iteration = try control.begin(context:&context)
            var retained: SystemVerilogConstantExpression?
            while let current = iteration {
                let integer = try current.value.binaryInt(signed:true,context:&context)
                precondition(integer == iterations-1)
                let body = try current.scope.entering(current.body,context:&context)
                for nested in 0..<current.body {
                    guard case .declaration(.localParameter,_,_,let initial?) = try syntax.node(at:nested).kind else {continue}
                    let expression = try SystemVerilogConstantExpression.prepare(node:initial,in:body,context:&context)
                    let evaluated = try expression.evaluate(width:32,context:&context).binaryInt(signed:true,context:&context)
                    precondition(evaluated == integer)
                    if retained == nil {retained = expression}
                }
                iterations += 1
                iteration = try control.resume(afterBody:current,value:current.value,context:&context)
            }
            let final = try control.finalValue?.binaryInt(signed:true,context:&context)
            let first = try retained?.evaluate(width:32,context:&context).binaryInt(signed:true,context:&context)
            precondition(final == 2 && first == -1)
        default:break
        }
    }
    precondition(iterations == 3 && selected != nil && selected == yes)
    try exerciseFrozenGenerateScopes(context: &context)
}

@available(macOS 26.0, *)
private nonisolated func exerciseFrozenGenerateScopes(context: inout LogicKernelContext) throws(LogicKernelError) {
    let fixtures = [
        ("module p; parameter i=1; for(genvar i=i;i<2;i++) begin: g for(genvar i=i;i<2;i++) begin: h end end endmodule", "b9cb1e21363226b356f38d05a4605d6941b9574e0d0eaab39cf107ce036ab662"),
        ("module p; for(genvar i=0;i<1;i++) begin: g localparam i=3; end endmodule", "cfff96b2d4e24f4406b43870c1bf4fb80c329459d5ff4a57852c266e64b2837a"),
        ("module p; genvar i; for(i=0;i<1;i++) begin: g for(i=0;i<1;i++) begin: h end end endmodule", "7c00f50a7b57a686e09459098f95b43b6803ce93ae848780232ade8e6b72e6b2"),
        ("module p; for(genvar i=0;i<2;i++) begin: g end endmodule", "bbd44f123195ee796363c81d49144f5de225218c0ab56f1605d518702eba206c")
    ]
    for (index, fixture) in fixtures.enumerated() {
        let bytes = Array(fixture.0.utf8)
        let artifact: ArtifactID
        do {
            artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256, hexadecimalValue: fixture.1), byteCount: UInt64(bytes.count))
        } catch { throw .invalidInput("Invalid probe artifact identity") }
        let source = try LogicSourceDocument(logicalName: "frozen-generate.sv", artifactID: artifact, bytes: bytes, context: &context)
        let tokens = try SystemVerilogByteLexer().tokenize(source, maximumTokens: 200, context: &context)
        let syntax = try SystemVerilogSyntaxParser.parse(tokens, limits: SystemVerilogSyntaxLimits(nodes: 200, children: 200, symbols: 40, nesting: 40), context: &context)
        let defaults = try SystemVerilogConstantEvaluator.evaluate(SystemVerilogParameterBinder.bind(syntax, module: syntax.child(at: syntax.modules.lowerBound), context: &context), context: &context)
        let root = try SystemVerilogConstantScope.module(defaults, context: &context)
        var inner: Int?; var outer: Int?
        for node in 0..<syntax.nodeCount {
            if case .generateFor = try syntax.node(at: node).kind { if inner == nil { inner = node }; outer = node }
        }
        guard let outer, let inner else { throw .invalidModel("Missing probe loop") }
        var control = try SystemVerilogStaticLoop.prepare(outer, in: root, context: &context)
        guard let current = try control.begin(context: &context) else { throw .invalidModel("Missing probe iteration") }
        if index == 0 {
            let outerValue = try current.value.binaryInt(signed: true, context: &context)
            precondition(outerValue == 1)
            let body = try current.scope.entering(current.body, context: &context)
            var nested = try SystemVerilogStaticLoop.prepare(inner, in: body, context: &context)
            guard let iteration = try nested.begin(context: &context) else { throw .invalidModel("Missing nested probe iteration") }
            let innerValue = try iteration.value.binaryInt(signed: true, context: &context)
            let exhausted = try nested.resume(afterBody: iteration, value: iteration.value, context: &context)
            precondition(innerValue == 1 && exhausted == nil)
            continue
        }
        do throws(LogicKernelError) {
            if index == 1 { _ = try current.scope.entering(current.body, context: &context) }
            else if index == 2 {
                let body = try current.scope.entering(current.body, context: &context)
                _ = try SystemVerilogStaticLoop.prepare(inner, in: body, context: &context)
            } else {
                let changed = try LogicFourStateVector(repeating: .one, width: LogicBitWidth(32), context: &context)
                _ = try control.resume(afterBody: current, value: changed, context: &context)
            }
            throw .invalidModel("Invalid generate semantics accepted by probe")
        } catch {
            guard case .sourceFailure(_, let origin, _) = error, origin.artifactID == artifact else { throw error }
        }
    }
}
