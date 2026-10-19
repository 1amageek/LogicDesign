import Foundation
import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicDesignSerialization
import LogicKernelProbeSupport
@testable import SystemVerilogFrontend

@Suite(.timeLimit(.minutes(1)))
struct ExpressionResolutionTests {
    @available(macOS 15.0, *)
    private func context(_ maximum: UInt64 = 20_000_000) throws -> LogicKernelContext {
        LogicKernelContext(limits: try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
            LogicResource.allCases.map { ($0, maximum) })), control: LogicCancellationSource())
    }
    @available(macOS 26.0, *)
    private func defaults(_ text: String, context: inout LogicKernelContext) throws -> SystemVerilogParameterDefaults {
        let bytes = Array(text.utf8)
        let source = try LogicSourceDocument(logicalName: "scopes.sv", artifactID: ArtifactID(digest: ContentDigest(
            algorithm: .sha256, hexadecimalValue: LogicSourceDigest.sha256HexadecimalValue(of: Data(bytes))),
            byteCount: UInt64(bytes.count)), bytes: bytes, context: &context)
        let tokens = try SystemVerilogByteLexer().tokenize(source, maximumTokens: bytes.count + 1, context: &context)
        let syntax = try SystemVerilogSyntaxParser.parse(tokens, limits: SystemVerilogSyntaxLimits(
            nodes: bytes.count, children: bytes.count, symbols: bytes.count, nesting: 100), context: &context)
        return try SystemVerilogConstantEvaluator.evaluate(SystemVerilogParameterBinder.bind(syntax,
            module: syntax.child(at: syntax.modules.lowerBound), context: &context), context: &context)
    }
    private func node(_ defaults: SystemVerilogParameterDefaults, _ predicate: (SystemVerilogSyntaxNode.Kind) -> Bool,
        ordinal: Int = 0) throws -> Int {
        var found = 0
        for index in 0..<defaults.bindings.syntax.nodeCount {
            if predicate(try defaults.bindings.syntax.node(at: index).kind) {
                if found == ordinal { return index }; found += 1
            }
        }
        throw LogicKernelError.invalidInput("Fixture syntax node not found")
    }


    @available(macOS 26.0, *)
    private func compile(_ declarations:String,_ expression:String,width:Int? = nil,signed:Bool? = nil,
        context:inout LogicKernelContext)throws->(model:ElaboratedRTL,result:SystemVerilogResolvedExpression,types:[SystemVerilogConstantType]) {
        let defaults = try defaults("module p; \(declarations) child #(\(expression)) u(); endmodule",context:&context)
        let scope = try SystemVerilogConstantScope.module(defaults,context:&context)
        var builder = try ElaboratedRTLBuilder(topModuleID:DesignEntityID(rawValue:9000),capacity:RTLResolvedCapacity(signals:20,expressions:300,operands:600,statements:0,children:0,caseItems:0,caseMatches:0,ports:0,processes:0),context:&context)
        var bindings:[SystemVerilogSignalBinding] = [];var types:[SystemVerilogConstantType] = []
        for entry in scope.storage.entries {
            guard case .declaration(let kind,_,let typeNode,_) = try defaults.bindings.syntax.node(at:entry.declaration).kind,
                  kind == .variable || kind == .net else {continue}
            let type = try SystemVerilogConstantEvaluator.withExpressionWorkspace(defaults,scope:scope,context:&context) {
                (evaluator,context) throws(LogicKernelError) in try evaluator.declarationType(typeNode,inferred:nil,context:&context)
            }
            let signal = try builder.addSignal(RTLResolvedSignal(id:DesignEntityID(rawValue:UInt64(bindings.count+1)),type:WordLogicType(width:type.width,isSigned:type.isSigned)),context:&context)
            bindings.append(SystemVerilogSignalBinding(declaration:entry.declaration,type:type,signal:signal));types.append(type)
        }
        let bound = try SystemVerilogSignalScope.bind(scope,signals:bindings,context:&context)
        let argument = try node(defaults,{if case .binding(_,let value?) = $0 {return value >= 0};return false})
        guard case .binding(_,let value?) = try defaults.bindings.syntax.node(at:argument).kind else {throw LogicKernelError.invalidInput("Expected argument")}
        var next:UInt64 = 100
        let result = try SystemVerilogExpressionCompiler.compile(value,in:bound,width:width,signed:signed,builder:&builder,nextEntityID:&next,context:&context)
        return (try builder.finish(context:&context),result,types)
    }
    @available(macOS 26.0, *)
    private func vector(_ value:UInt64,width:LogicBitWidth,context:inout LogicKernelContext)throws->LogicFourStateVector {
        _ = try context.reserveStorage(byteCount:UInt64(width.wordCount) * 16)
        var words = [UInt64](repeating:0,count:width.wordCount);words[0] = value & (width.wordCount == 1 ? width.tailMask : .max)
        return try LogicFourStateVector(width:width,valueWords:words,unknownWords:[UInt64](repeating:0,count:width.wordCount))
    }
    @available(macOS 26.0, *)
    private func integer(_ program:(model:ElaboratedRTL,result:SystemVerilogResolvedExpression,types:[SystemVerilogConstantType]),
        _ values:[UInt64],context:inout LogicKernelContext)throws->UInt64 {
        var inputs:[LogicFourStateVector] = []
        for index in values.indices {inputs.append(try vector(values[index],width:program.types[index].width,context:&context))}
        let value = try ProbeRTLExpressionEvaluator.evaluate(program.model,signals:inputs,result:program.result.index,context:&context)
        return try UInt64(value.binaryInt(signed:false,context:&context))
    }
    @Test func contextualCarryAndSignednessArePreservedAcrossAllSmallInputs() throws {
        guard #available(macOS 26.0, *) else {Issue.record("Requires macOS 26");return}
        var run = try context(500_000_000)
        for declaration in ["logic [3:0] a,b;","logic signed [3:0] a,b;","logic signed [3:0] a;logic [3:0] b;"] {
            let signed = declaration == "logic signed [3:0] a,b;"
            let program = try compile(declaration,"a+b",width:8,context:&run)
            for a in UInt64(0)..<16 {for b in UInt64(0)..<16 {
                let lhs = signed && a >= 8 ? Int(a)-16 : Int(a)
                let rhs = signed && b >= 8 ? Int(b)-16 : Int(b)
                #expect(try integer(program,[a,b],context:&run) == UInt64((lhs+rhs)&255))
            }}
        }
        let carry = try compile("logic [7:0] a;","a+8'd1",width:9,context:&run)
        #expect(try integer(carry,[255],context:&run) == 256)
        let truncated = try compile("logic [7:0] a;","a+8'd1",width:4,context:&run)
        #expect(try integer(truncated,[31],context:&run) == 0)
    }
    @Test func operatorsCastsComparisonsAndShiftCountsUseExplicitTypes() throws {
        guard #available(macOS 26.0, *) else {Issue.record("Requires macOS 26");return}
        var run = try context(500_000_000)
        let operations:[(String,(Int,Int)->Int)] = [
            ("a-b",{$0-$1}),("a*b",{$0*$1}),("a~^b",{~($0 ^ $1)}),
            ("a<b",{$0<$1 ? 1:0}),("a<=b",{$0<=$1 ? 1:0}),("a>b",{$0>$1 ? 1:0}),("a>=b",{$0>=$1 ? 1:0}),
            ("a===b",{$0==$1 ? 1:0}),("a!==b",{$0 != $1 ? 1:0}),
            ("a?b:~b",{$0 != 0 ? $1 : ~$1})]
        for (expression,expected) in operations {
            let program = try compile("logic [3:0] a,b;",expression,width:8,context:&run)
            for a in UInt64(0)..<16 {for b in UInt64(0)..<16 {
                #expect(try integer(program,[a,b],context:&run) == UInt64(expected(Int(a),Int(b))&255))
            }}
        }
        for (expression,expected) in [("a>>>b",UInt64(255)),("$unsigned(a)>>>b",UInt64(3)),("$signed(a)>>b",UInt64(63)),("a<<b",UInt64(252))] {
            let program = try compile("logic signed [3:0] a;logic [3:0] b;",expression,width:8,context:&run)
            #expect(try integer(program,[15,2],context:&run) == expected)
        }
    }
    @Test func concatenationRepetitionAndPackedSelectionsPreserveDirection() throws {
        guard #available(macOS 26.0, *) else {Issue.record("Requires macOS 26");return}
        var run = try context()
        let concatenation = try compile("logic [3:0] a;","{2'b10,{0{a}},{2{a}},2'b01}",context:&run)
        #expect(try integer(concatenation,[3],context:&run) == 2253)
        let ascending = try compile("logic [0:7] a;","a[2 +: 3]",context:&run)
        #expect(try integer(ascending,[0xb2],context:&run) == 6)
        let multidimensional = try compile("logic [1:0][0:3] a;","a[1][1 +: 2]",context:&run)
        #expect(try integer(multidimensional,[0xb2],context:&run) == 1)
    }
    @Test func dynamicSelectionsNormalizeSignedUnsignedAndMultidimensionalIndices() throws {
        guard #available(macOS 26.0, *) else {Issue.record("Requires macOS 26");return}
        var run = try context(20_000_000)
        for (declaration,expected) in [("logic [7:0] a;logic [2:0] i;",[0,1,0,0,1,1,0,1]),("logic [0:7] a;logic [2:0] i;",[1,0,1,1,0,0,1,0])] {
            let program = try compile(declaration,"a[i]",context:&run)
            for i in 0..<8 {#expect(try integer(program,[0xb2,UInt64(i)],context:&run) == UInt64(expected[i]))}
        }
        let chunks = try compile("logic [1:0][3:0] a;logic i;","a[i]",context:&run)
        #expect(try integer(chunks,[0xb2,0],context:&run) == 2)
        #expect(try integer(chunks,[0xb2,1],context:&run) == 11)
        let part = try compile("logic [0:7] a;logic [2:0] i;","a[i +: 3]",context:&run)
        #expect(try integer(part,[0xb2,2],context:&run) == 6)
        for (declaration,selection,index) in [("logic [7:0] a;logic [2:0] i;","a[i -: 3]",5),("logic [0:7] a;logic [2:0] i;","a[i -: 3]",4)] {
            let program = try compile(declaration,selection,context:&run)
            #expect(try integer(program,[0xb2,UInt64(index)],context:&run) == 6)
        }
        let large = try compile("logic [0:7] a;logic [64:0] i;","a[i]",context:&run)
        _ = try run.reserveStorage(byteCount:32)
        let huge = try LogicFourStateVector(width:large.types[1].width,valueWords:[0,1],unknownWords:[0,0])
        let outOfRange = try ProbeRTLExpressionEvaluator.evaluate(large.model,signals:[vector(0xb2,width:large.types[0].width,context:&run),huge],result:large.result.index,context:&run)
        #expect(try outOfRange.bit(at:0) == .unknown)
        let invalid = try compile("logic [7:0] a;int i;","a[i]",context:&run)
        let index = try vector(UInt64(UInt32.max),width:invalid.types[1].width,context:&run)
        let value = try ProbeRTLExpressionEvaluator.evaluate(invalid.model,signals:[vector(0xb2,width:invalid.types[0].width,context:&run),index],result:invalid.result.index,context:&run)
        #expect(try value.bit(at:0) == .unknown)
    }
    @Test func runtimeCannotBecomeAConstantOrOverrideItsDeclarationType() throws {
        guard #available(macOS 26.0, *) else {Issue.record("Requires macOS 26");return}
        var run = try context()
        #expect(throws:LogicKernelError.self) {try compile("logic [3:0] a;","{a{1'b1}}",context:&run)}
        #expect(throws:LogicKernelError.self) {try compile("logic [3:0] a;logic [1:0] i;","a[i:0]",context:&run)}
        let defaults = try defaults("module p; logic [3:0] a; endmodule",context:&run)
        let scope = try SystemVerilogConstantScope.module(defaults,context:&run)
        let declaration = try node(defaults,{if case .declaration(.variable,_,_,_) = $0{return true};return false})
        #expect(throws:LogicKernelError.self) {try SystemVerilogSignalScope.bind(scope,signals:[],context:&run)}
        #expect(throws:LogicKernelError.self) {try SystemVerilogSignalScope.bind(scope,signals:[SystemVerilogSignalBinding(declaration:declaration,type:SystemVerilogConstantType(width:5),signal:RTLSignalIndex(0))],context:&run)}
    }
    @Test func exactScopeOwnershipAliasesAndResourceFailuresAreEnforced() throws {
        guard #available(macOS 26.0, *) else {Issue.record("Requires macOS 26");return}
        var run = try context()
        let defaults = try defaults("module p; logic [3:0] a,b; child #(a+b) u(); endmodule",context:&run)
        let scope = try SystemVerilogConstantScope.module(defaults,context:&run)
        let a = try node(defaults,{if case .declaration(.variable,_,_,_) = $0{return true};return false})
        let b = try node(defaults,{if case .declaration(.variable,_,_,_) = $0{return true};return false},ordinal:1)
        let t = try SystemVerilogConstantType(width:4,dimensions:[SystemVerilogPackedDimension(left:3,right:0)])
        let bound = try SystemVerilogSignalScope.bind(scope,signals:[SystemVerilogSignalBinding(declaration:a,type:t,signal:RTLSignalIndex(0)),SystemVerilogSignalBinding(declaration:b,type:t,signal:RTLSignalIndex(0))],context:&run)
        #expect(bound.constants.storage === scope.storage)
        #expect(throws:LogicKernelError.self) {try SystemVerilogSignalScope.bind(scope,parent:bound,signals:[],context:&run)}
        let expression = try node(defaults,{if case .binary(.add,_,_) = $0{return true};return false})
        var builder = try ElaboratedRTLBuilder(topModuleID:DesignEntityID(rawValue:999),capacity:RTLResolvedCapacity(signals:1,expressions:20,operands:40,statements:0,children:0,caseItems:0,caseMatches:0,ports:0,processes:0),context:&run)
        _ = try builder.addSignal(RTLResolvedSignal(id:DesignEntityID(rawValue:1),type:WordLogicType(width:t.width)),context:&run)
        var next:UInt64 = 0
        #expect(throws:LogicKernelError.self) {try SystemVerilogExpressionCompiler.compile(expression,in:bound,builder:&builder,nextEntityID:&next,context:&run)}
        next = 100
        let cancel = LogicCancellationSource();cancel.cancel()
        var cancelled = LogicKernelContext(limits:run.limits,control:cancel)
        #expect(throws:LogicKernelError.cancelled) {try SystemVerilogExpressionCompiler.compile(expression,in:bound,builder:&builder,nextEntityID:&next,context:&cancelled)}
        #expect(cancelled.usage[.allocationBytes] == 0)
        var tight = LogicKernelContext(limits:try LogicKernelLimits(maximums:Dictionary(uniqueKeysWithValues:LogicResource.allCases.map {($0,$0 == .managedStorageBytes ? 1 : 1_000_000)})),control:LogicCancellationSource())
        #expect(throws:LogicKernelError.self) {try SystemVerilogExpressionCompiler.compile(expression,in:bound,builder:&builder,nextEntityID:&next,context:&tight)}
        #expect(tight.usage[.allocationBytes] == 0)
    }

    @Test func nearestRuntimeAndConstantDeclarationsShadowOuterSignals() throws {
        guard #available(macOS 26.0, *) else {Issue.record("Requires macOS 26");return}
        var run = try context()
        for constantInside in [true,false] {
            let text = constantInside ? "module p; logic [3:0] a; if(1) begin: g localparam a=3;logic [3:0] b;child #(a+b) u();end endmodule" : "module p; parameter a=7;if(1) begin: g logic [3:0] a;child #(a+1) u();end endmodule"
            let defaults = try defaults(text,context:&run)
            let constants = try SystemVerilogConstantScope.module(defaults,context:&run)
            let block = try node(defaults,{if case .generateBlock = $0{return true};return false})
            let inner = try constants.entering(block,context:&run)
            let type = try SystemVerilogConstantType(width:4,dimensions:[SystemVerilogPackedDimension(left:3,right:0)])
            let outerDeclaration = try node(defaults,{if case .declaration(.variable,_,_,_) = $0{return true};return false})
            let innerDeclaration = try node(defaults,{if case .declaration(.variable,_,_,_) = $0{return true};return false},ordinal:constantInside ? 1:0)
            let root = try SystemVerilogSignalScope.bind(constants,signals:constantInside ? [SystemVerilogSignalBinding(declaration:outerDeclaration,type:type,signal:RTLSignalIndex(0))]:[],context:&run)
            let scope = try SystemVerilogSignalScope.bind(inner,parent:root,signals:[SystemVerilogSignalBinding(declaration:innerDeclaration,type:type,signal:RTLSignalIndex(constantInside ? 1:0))],context:&run)
            let binding = try node(defaults,{if case .binding(_,let value?) = $0{return value >= 0};return false})
            guard case .binding(_,let expression?) = try defaults.bindings.syntax.node(at:binding).kind else {throw LogicKernelError.invalidInput("Missing argument")}
            var builder = try ElaboratedRTLBuilder(topModuleID:DesignEntityID(rawValue:9000),capacity:RTLResolvedCapacity(signals:2,expressions:50,operands:100,statements:0,children:0,caseItems:0,caseMatches:0,ports:0,processes:0),context:&run)
            for index in 0..<(constantInside ? 2:1) {_ = try builder.addSignal(RTLResolvedSignal(id:DesignEntityID(rawValue:UInt64(index+1)),type:WordLogicType(width:type.width)),context:&run)}
            var next:UInt64 = 100
            #expect(throws:LogicKernelError.self) {try SystemVerilogExpressionCompiler.compile(expression,in:root,builder:&builder,nextEntityID:&next,context:&run)}
            let result = try SystemVerilogExpressionCompiler.compile(expression,in:scope,width:5,builder:&builder,nextEntityID:&next,context:&run)
            let model = try builder.finish(context:&run)
            let values = constantInside ? [try vector(15,width:type.width,context:&run),try vector(5,width:type.width,context:&run)]:[try vector(15,width:type.width,context:&run)]
            let evaluated = try ProbeRTLExpressionEvaluator.evaluate(model,signals:values,result:result.index,context:&run).binaryInt(signed:false,context:&run)
            #expect(evaluated == (constantInside ? 8:16))
        }
    }

}
