import Foundation
import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicDesignSerialization
@testable import SystemVerilogFrontend

@Suite(.timeLimit(.minutes(1)))
struct StaticScopeTests {
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
    private func block(_ defaults: SystemVerilogParameterDefaults, label: String) throws -> Int {
        let syntax = defaults.bindings.syntax
        return try node(defaults, { kind in
            let symbol: Int
            switch kind {
            case .block(let name?, _), .generateBlock(let name?, _): symbol = name
            default: return false
            }
            do {
                let range = try syntax.symbolRange(at: symbol)
                let spelling = Array(label.utf8)
                return syntax.source.withBytes { bytes in
                    guard range.count == spelling.count else { return false }
                    for index in spelling.indices { if bytes[range.lowerBound + index] != spelling[index] { return false } }
                    return true
                }
            } catch { return false }
        })
    }
    private func instance(_ defaults: SystemVerilogParameterDefaults, ordinal: Int = 0) throws -> Int {
        try node(defaults, { if case .instance = $0 { return true }; return false }, ordinal: ordinal)
    }
    private func argument(_ defaults: SystemVerilogParameterDefaults, instance: Int) throws -> Int {
        let syntax = defaults.bindings.syntax
        guard case .instance(_, _, let parameters, _) = try syntax.node(at: instance).kind,
              case .binding(_, let value?) = try syntax.node(at: syntax.child(at: parameters.lowerBound)).kind else {
            throw LogicKernelError.invalidInput("Expected parameter argument")
        }
        return value
    }
    @available(macOS 26.0, *)
    private func integer(_ scope: SystemVerilogConstantScope, expression: Int, width: Int = 32,
        context: inout LogicKernelContext) throws -> Int {
        let expression = try SystemVerilogConstantExpression.prepare(node: expression, in: scope, context: &context)
        return try expression.evaluate(width: width, context: &context).binaryInt(signed: expression.type.isSigned, context: &context)
    }
    @Test func nestedLocalParametersShadowAncestorsAndRetainPackedTypes() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let input = try defaults("module p; parameter A=8'hff; if(1) begin: outer localparam [8:0] B=A+8'd1; if(1) begin: inner localparam [2:0] A=3; localparam [B-1:0] MASK='1; child #(A+B+MASK[255]) u(); end end endmodule", context:&run)
        let root = try SystemVerilogConstantScope.module(input, context:&run)
        let outer = try root.entering(block(input,label:"outer"), context:&run)
        let inner = try outer.entering(block(input,label:"inner"), context:&run)
        #expect(try integer(inner, expression:argument(input,instance:instance(input)), context:&run) == 260)
        #expect(try root.owns(instance(input), context:&run) == false)
        #expect(try inner.owns(instance(input), context:&run))
    }
    @Test func nearestRuntimeAndPendingNamesDoNotFallBackToModuleParameters() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for body in ["logic A; localparam B=A;", "localparam B=A; localparam A=2;", "localparam A=A+1;", "genvar A; localparam B=A;"] {
            var run = try context()
            let input = try defaults("module p; parameter A=7; if(1) begin: scope \(body) end endmodule",context:&run)
            let root = try SystemVerilogConstantScope.module(input,context:&run)
            do {
                _ = try root.entering(block(input,label:"scope"),context:&run)
                Issue.record("A blocked lexical constant was accepted: \(body)")
            } catch let error as LogicKernelError {
                guard case .sourceFailure(let code,let source,_) = error else { throw error }
                #expect(code.rawValue == "SV_SCOPE_NONCONSTANT_NAME")
                #expect(source.artifactID == input.bindings.syntax.source.root.artifactID)
                let bytes = Array(("module p; parameter A=7; if(1) begin: scope \(body) end endmodule").utf8)
                #expect(String(decoding:bytes[Int(source.byteRange.lowerBound)..<Int(source.byteRange.upperBound)],as:UTF8.self) == "A")
            }
        }
    }
    @Test func directExpressionOwnershipAndSiblingScopesAreExact() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let input = try defaults("module p; parameter A=1; if(1) begin: first localparam A=2; child #(A) u(); end else begin: second localparam A=3; child #(A) v(); end endmodule",context:&run)
        let root = try SystemVerilogConstantScope.module(input,context:&run)
        let first = try root.entering(block(input,label:"first"),context:&run)
        let second = try root.entering(block(input,label:"second"),context:&run)
        let a = try argument(input,instance:instance(input)); let b = try argument(input,instance:instance(input,ordinal:1))
        #expect(try integer(first,expression:a,context:&run) == 2)
        #expect(try integer(second,expression:b,context:&run) == 3)
        for scope in [root,second] {
            #expect(throws: LogicKernelError.self) { try SystemVerilogConstantExpression.prepare(node:a,in:scope,context:&run) }
        }
        #expect(throws: LogicKernelError.self) { try first.entering(block(input,label:"second"),context:&run) }
    }
    @Test func duplicateLocalNamesAndRuntimeRootShadowingAreRefused() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let input = try defaults("module p; if(1) begin: scope localparam A=1; logic A; end endmodule",context:&run)
        let root = try SystemVerilogConstantScope.module(input,context:&run)
        do { _ = try root.entering(block(input,label:"scope"),context:&run); Issue.record("Duplicate name accepted") }
        catch let error as LogicKernelError {
            guard case .sourceFailure(let code,_,_) = error else { throw error }
            #expect(code.rawValue == "SV_SCOPE_DUPLICATE_NAME")
        }
        let ports = try defaults("module p(a); input a; child #(a) u(); endmodule",context:&run)
        let portScope = try SystemVerilogConstantScope.module(ports,context:&run)
        #expect(throws: LogicKernelError.self) { try integer(portScope,expression:argument(ports,instance:instance(ports)),context:&run) }
    }
    @Test func frozenGenvarIterationsAreIndependentAndPreserveChildContextCarry() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let input = try defaults("module p; for(genvar i=0;i<4;i++) begin: g localparam [7:0] A=8'hff-i; child #(A+8'd1) u(); end endmodule",context:&run)
        let child = try defaults("module child #(parameter [8:0] A=0); endmodule",context:&run).bindings
        let root = try SystemVerilogConstantScope.module(input,context:&run)
        let loop = try node(input,{if case .generateFor = $0 {return true};return false})
        let body = try block(input,label:"g")
        var retained: [SystemVerilogConstantExpression] = []
        for index in 0..<4 {
            let value = try LogicFourStateVector(width:LogicBitWidth(32),valueWords:[UInt64(index)],unknownWords:[0])
            let iteration = try root.iteration(of:loop,value:value,context:&run)
            let selected = try iteration.entering(body,context:&run)
            let result = try SystemVerilogInstanceParameterResolver.evaluate(instance:instance(input),in:selected,child:child,context:&run)
            #expect(try result.value(forDeclaration:child.declaration(at:0)).value.binaryInt(signed:false,context:&run) == 256-index)
            retained.append(try SystemVerilogConstantExpression.prepare(node:argument(input,instance:instance(input)),in:selected,context:&run))
        }
        for index in retained.indices {
            #expect(try retained[index].evaluate(width:9,context:&run).binaryInt(signed:false,context:&run) == 256-index)
        }
        #expect(throws: LogicKernelError.self) { try root.entering(loop,context:&run) }
        let short = try LogicFourStateVector(width:LogicBitWidth(8),valueWords:[0],unknownWords:[0])
        #expect(throws: LogicKernelError.self) { try root.iteration(of:loop,value:short,context:&run) }
    }
    @Test func proceduralIterationValuesRemainUsableOutsideConstantDeclarations() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let input = try defaults("module p; parameter W=5; logic [4:0] y; always_comb for(logic [W-1:0] i=0;i<4;i++) begin: b localparam A=W-1; y=i+A; end endmodule",context:&run)
        let root = try SystemVerilogConstantScope.module(input,context:&run)
        let loop = try node(input,{if case .forStatement = $0{return true};return false})
        let value = try LogicFourStateVector(width:LogicBitWidth(5),valueWords:[3],unknownWords:[0])
        let iteration = try root.iteration(of:loop,value:value,context:&run)
        let body = try iteration.entering(block(input,label:"b"),context:&run)
        // Locate the assignment's RHS rather than depending on spelling or node ordering.
        let assignment = try node(input,{if case .assignment(.blocking,_,_) = $0{return true};return false})
        guard case .assignment(_,_,let expression?) = try input.bindings.syntax.node(at:assignment).kind else { throw LogicKernelError.invalidInput("Missing assignment") }
        #expect(try integer(body,expression:expression,context:&run) == 7)
    }
    @Test func scopedChildOverridesRejectWrongScopeAndRemainSourceBound() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let input = try defaults("module p; parameter A=1; if(1) begin: g localparam [7:0] A=8'hff; child #(.A(A+8'd1)) u(); end endmodule",context:&run)
        let child = try defaults("module child #(parameter [8:0] A=0); endmodule",context:&run).bindings
        let root = try SystemVerilogConstantScope.module(input,context:&run)
        let selected = try root.entering(block(input,label:"g"),context:&run)
        let result = try SystemVerilogInstanceParameterResolver.evaluate(instance:instance(input),in:selected,child:child,context:&run)
        let constant = try result.value(forDeclaration:child.declaration(at:0))
        #expect(try constant.value.binaryInt(signed:false,context:&run) == 256)
        #expect(constant.origin.artifactID == input.bindings.syntax.source.root.artifactID)
        #expect(throws: LogicKernelError.self) { try SystemVerilogInstanceParameterResolver.evaluate(instance:instance(input),in:root,child:child,context:&run) }
    }
    @Test func implicitGenerateBodiesDoNotHoistBranchDeclarations() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let input = try defaults("module p; parameter A=7; if(1) localparam A=2; else localparam A=3; child #(A) u(); case(0) 0: child #(A+1) v(); default: child #(A+2) w(); endcase endmodule",context:&run)
        let root = try SystemVerilogConstantScope.module(input,context:&run)
        #expect(try integer(root,expression:argument(input,instance:instance(input)),context:&run) == 7)
        for ordinal in 1...2 {
            let target = try instance(input,ordinal:ordinal)
            let arm = try node(input,{if case .caseArm = $0{return true};return false},ordinal:ordinal-1)
            guard case .caseArm(_,let body) = try input.bindings.syntax.node(at:arm).kind else {throw LogicKernelError.invalidInput("Missing generate arm")}
            let branch = try root.entering(body,context:&run)
            #expect(try integer(branch,expression:argument(input,instance:target),context:&run) == 7+ordinal)
            #expect(try branch.owns(target,context:&run))
        }
    }
    @Test func mutuallyExclusiveLabelsAreLegalButSimultaneousAndDuplicatePortsAreRejected() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        for control in ["if(1) begin: g localparam A=1; end else begin: g localparam A=2; end",
                        "case(0) 0: begin: g localparam A=1; end default: begin: g localparam A=2; end endcase"] {
            let input = try defaults("module p; \(control) endmodule",context:&run)
            _ = try SystemVerilogConstantScope.module(input,context:&run)
        }
        for text in ["module p; begin: g end begin: g end endmodule", "module p(a,a); input a; endmodule",
                     "module p(input a,input a); endmodule", "module p(a); input a; output a; endmodule"] {
            let input = try defaults(text,context:&run)
            #expect(throws: LogicKernelError.self) { try SystemVerilogConstantScope.module(input,context:&run) }
        }
    }
    @Test func externalLoopTargetsBindAndUnknownIterationsFailExplicitly() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let input = try defaults("module p; genvar j; for(j=0;j<2;j++) begin: a end for(genvar i=0;i<2;i++) begin: b end endmodule",context:&run)
        let root = try SystemVerilogConstantScope.module(input,context:&run)
        let known = try LogicFourStateVector(width:LogicBitWidth(32),valueWords:[0],unknownWords:[0])
        let unknown = try LogicFourStateVector(width:LogicBitWidth(32),valueWords:[0],unknownWords:[1])
        let external = try node(input,{if case .generateFor = $0{return true};return false})
        let inline = try node(input,{if case .generateFor = $0{return true};return false},ordinal:1)
        let bound = try root.iteration(of:external,value:known,context:&run)
        #expect(bound.container == external)
        do { _ = try root.iteration(of:inline,value:unknown,context:&run); Issue.record("Unknown iteration accepted") }
        catch {
            guard case .sourceFailure(let code,let source,_) = error else {throw error}
            #expect(code.rawValue == "SV_SCOPE_ITERATION_BINARY" && source.artifactID == input.bindings.syntax.source.root.artifactID)
        }
    }
    @Test func retainedScopeHandlesCanEvaluateConcurrentlyWithSeparateContexts() async throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let input = try defaults("module p; parameter A=1; if(1) begin: g localparam A=8'hff; child #(A+8'd1) u(); end endmodule",context:&run)
        let root = try SystemVerilogConstantScope.module(input,context:&run)
        let selected = try root.entering(block(input,label:"g"),context:&run)
        let handle = try SystemVerilogConstantExpression.prepare(node:argument(input,instance:instance(input)),in:selected,context:&run)
        try await withThrowingTaskGroup(of:Int.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    var taskContext = try context()
                    return try handle.evaluate(width:9,context:&taskContext).binaryInt(signed:false,context:&taskContext)
                }
            }
            for try await value in group {#expect(value == 256)}
        }
    }
    @Test func moduleParameterHandleCannotEscapeIntoNestedShadowing() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let input = try defaults("module p; parameter A=1; if(1) begin: g localparam A=2; child #(A) u(); end endmodule",context:&run)
        let expression = try argument(input,instance:instance(input))
        #expect(throws: LogicKernelError.self) {
            try SystemVerilogConstantExpression.prepare(node:expression,in:input,context:&run)
        }
    }
    @Test func directlyNestedConditionalGenerateSharesTheEnclosingScope() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let input = try defaults("module p; parameter A=7; if(1) if(A) begin: g child #(A) u(); end else begin: g child #(A+1) v(); end else begin: g child #(A+2) w(); end endmodule",context:&run)
        let root = try SystemVerilogConstantScope.module(input,context:&run)
        let inner = try node(input,{if case .generateIf = $0{return true};return false})
        guard case .generateIf(let condition,_,_) = try input.bindings.syntax.node(at:inner).kind else {throw LogicKernelError.invalidInput("Missing nested conditional")}
        #expect(try root.owns(condition,context:&run))
        let handle = try SystemVerilogConstantExpression.prepare(node:condition,in:input,context:&run)
        #expect(try handle.evaluate(width:32,context:&run).binaryInt(signed:false,context:&run) == 7)
        for ordinal in 0..<3 {
            let body = try node(input,{if case .generateBlock = $0{return true};return false},ordinal:ordinal)
            let selected = try root.entering(body,context:&run)
            #expect(try integer(selected,expression:argument(input,instance:instance(input,ordinal:ordinal)),context:&run) == 7+ordinal)
        }
    }
    @Test func scopeCancellationAndStorageAdmissionPrecedePublication() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let input = try defaults("module p; if(1) begin: g localparam A=2; end endmodule",context:&run)
        let root = try SystemVerilogConstantScope.module(input,context:&run)
        let control = LogicCancellationSource(); control.cancel()
        var cancelled = LogicKernelContext(limits:run.limits,control:control)
        #expect(throws: LogicKernelError.cancelled) { try root.entering(block(input,label:"g"),context:&cancelled) }
        #expect(cancelled.usage[.allocationBytes] == 0)
        var tight = try context(1)
        #expect(throws: LogicKernelError.self) { try SystemVerilogConstantScope.module(input,context:&tight) }
        #expect(tight.usage[.allocationBytes] == 0)
        var maximums = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(20_000_000)) })
        maximums[.workUnits] = 1
        var limited = LogicKernelContext(limits:try LogicKernelLimits(maximums:maximums),control:LogicCancellationSource())
        try limited.charge(.workUnits)
        #expect(throws: LogicKernelError.self) { try SystemVerilogConstantScope.module(input,context:&limited) }
        #expect(limited.usage[.allocationBytes] > 0)
        #expect(limited.usage[.managedStorageBytes] == 0)
    }
}
