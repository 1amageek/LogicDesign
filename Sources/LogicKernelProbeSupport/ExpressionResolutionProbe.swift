import CircuiteFoundation
import LogicIR
import LogicKernelCore
import SystemVerilogFrontend

@available(macOS 26.0, *)
public nonisolated func exerciseExpressionResolutionContract() throws {
    let limits = try LogicKernelLimits(maximums:Dictionary(uniqueKeysWithValues:LogicResource.allCases.map {($0,UInt64(8_000_000))}))
    var context = LogicKernelContext(limits:limits,control:LogicCancellationSource())
    let text = "module p; logic signed [3:0] a; logic [3:0] b; logic [0:7] v; logic [2:0] i; child #(a+b,v[i]) u(); endmodule"
    let artifact = try ArtifactID(digest:ContentDigest(algorithm:.sha256,hexadecimalValue:"ef4f09ab5bb2a5131e9995d508a6be7493e9d0a7be3d80d8788ab9c53a3f2f3f"),byteCount:109)
    let source = try LogicSourceDocument(logicalName:"expressions.sv",artifactID:artifact,bytes:Array(text.utf8),context:&context)
    let tokens = try SystemVerilogByteLexer().tokenize(source,maximumTokens:200,context:&context)
    let syntax = try SystemVerilogSyntaxParser.parse(tokens,limits:SystemVerilogSyntaxLimits(nodes:200,children:200,symbols:40,nesting:40),context:&context)
    let defaults = try SystemVerilogConstantEvaluator.evaluate(SystemVerilogParameterBinder.bind(syntax,module:syntax.child(at:syntax.modules.lowerBound),context:&context),context:&context)
    let constants = try SystemVerilogConstantScope.module(defaults,context:&context)
    var builder = try ElaboratedRTLBuilder(topModuleID:DesignEntityID(rawValue:9000),capacity:RTLResolvedCapacity(signals:4,expressions:100,operands:200,statements:0,children:0,caseItems:0,caseMatches:0,ports:0,processes:0),context:&context)
    var bindings:[SystemVerilogSignalBinding] = []
    for node in 0..<syntax.nodeCount {
        guard case .declaration(.variable,_,_,_) = try syntax.node(at:node).kind else {continue}
        let ordinal = bindings.count
        let left = ordinal == 2 ? 0 : ordinal == 3 ? 2 : 3
        let right = ordinal == 2 ? 7 : 0
        let type = try SystemVerilogConstantType(width:ordinal == 2 ? 8 : ordinal == 3 ? 3 : 4,
            signed:ordinal == 0,dimensions:[SystemVerilogPackedDimension(left:left,right:right)])
        let signal = try builder.addSignal(RTLResolvedSignal(id:DesignEntityID(rawValue:UInt64(ordinal+1)),type:WordLogicType(width:type.width,isSigned:type.isSigned)),context:&context)
        bindings.append(SystemVerilogSignalBinding(declaration:node,type:type,signal:signal))
    }
    let scope = try SystemVerilogSignalScope.bind(constants,signals:bindings,context:&context)
    var next:UInt64 = 100
    var results:[SystemVerilogResolvedExpression] = []
    for node in 0..<syntax.nodeCount {
        guard case .binding(_,let value?) = try syntax.node(at:node).kind else {continue}
        results.append(try SystemVerilogExpressionCompiler.compile(value,in:scope,width:results.isEmpty ? 8 : nil,
            builder:&builder,nextEntityID:&next,context:&context))
    }
    let model = try builder.finish(context:&context)
    precondition(bindings.count == 4 && results.count == 2)
    for a in 0..<16 {for b in 0..<16 {
        let index = a % 8
        var inputs:[LogicFourStateVector] = []
        for (ordinal,value) in [a,b,0xb2,index].enumerated() {
            inputs.append(try LogicFourStateVector(width:bindings[ordinal].type.width,valueWords:[UInt64(value)],unknownWords:[0]))
        }
        let sum = try ProbeRTLExpressionEvaluator.evaluate(model,signals:inputs,result:results[0].index,context:&context).binaryInt(signed:false,context:&context)
        let selected = try ProbeRTLExpressionEvaluator.evaluate(model,signals:inputs,result:results[1].index,context:&context).binaryInt(signed:false,context:&context)
        precondition(sum == a+b && selected == ((0xb2 >> (7-index)) & 1))
    }}
}
