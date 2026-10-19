import Foundation
import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicDesignSerialization
@testable import SystemVerilogFrontend

@Suite(.timeLimit(.minutes(1)))
struct StaticControlTests {
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
    private func root(_ text: String, context: inout LogicKernelContext) throws -> SystemVerilogConstantScope {
        try SystemVerilogConstantScope.module(defaults(text, context: &context), context: &context)
    }
    @available(macOS 26.0, *)
    private func loop(_ scope: SystemVerilogConstantScope, ordinal: Int = 0) throws -> Int {
        try node(scope.defaults, { kind in
            switch kind { case .generateFor, .forStatement: return true; default: return false }
        }, ordinal: ordinal)
    }
    @available(macOS 26.0, *)
    private func number(_ n: Int, width: Int = 32, context: inout LogicKernelContext) throws -> LogicFourStateVector {
        let bits = try LogicBitWidth(width)
        _ = try context.reserveStorage(byteCount: UInt64(bits.wordCount) * 16)
        var words = [UInt64](repeating: n < 0 ? .max : 0, count: bits.wordCount)
        words[0] = UInt64(truncatingIfNeeded: n)
        words[bits.wordCount - 1] &= bits.tailMask
        return try LogicFourStateVector(width: bits, valueWords: words, unknownWords: [UInt64](repeating: 0, count: bits.wordCount))
    }
    private func required(_ value: SystemVerilogLoopIteration?) throws -> SystemVerilogLoopIteration {
        guard let value else { throw LogicKernelError.invalidInput("Expected a yielded iteration") }
        return value
    }
    @Test func caseCommonContextPrecedesArithmeticAndIncludesEveryArm() throws {
        guard #available(macOS 26.0, *) else { return }
        for header in ["case(8'h0f) 4'shf+4'sh0:", "case(4'shf+4'sh0) 8'h0f:"] {
            var run = try context()
            let scope = try root("module p; \(header) begin: yes end 8'h00: begin: no end endcase endmodule",context:&run)
            let selection = try node(scope.defaults,{if case .generateCase = $0{return true};return false})
            let first = try node(scope.defaults,{if case .generateBlock = $0{return true};return false})
            #expect(try SystemVerilogGenerateSelector.select(selection,in:scope,context:&run) == first)
        }
        var run = try context()
        let scope = try root("module p; case(4'shf) -32'sd1: begin: yes end 32'sd0: begin: no end endcase endmodule",context:&run)
        let selection = try node(scope.defaults,{if case .generateCase = $0{return true};return false})
        #expect(try SystemVerilogGenerateSelector.select(selection,in:scope,context:&run) == node(scope.defaults,{if case .generateBlock = $0{return true};return false}))
    }
    @Test func selectionUsesFirstMatchDefaultAndNoBodyWithoutElaboratingDeadDeclarations() throws {
        guard #available(macOS 26.0, *) else { return }
        var run = try context()
        let scope = try root("module p; if(0) begin: bad localparam A=missing; end else begin: good end case(1) 1: begin: first end 1: begin: second end default: begin: fallback end endcase if(0) begin: absent end endmodule",context:&run)
        let firstIf = try node(scope.defaults,{if case .generateIf = $0{return true};return false})
        let selected = try SystemVerilogGenerateSelector.select(firstIf,in:scope,context:&run)
        #expect(try selected == node(scope.defaults,{if case .generateBlock = $0{return true};return false},ordinal:1))
        let caseNode = try node(scope.defaults,{if case .generateCase = $0{return true};return false})
        #expect(try SystemVerilogGenerateSelector.select(caseNode,in:scope,context:&run) == node(scope.defaults,{if case .generateBlock = $0{return true};return false},ordinal:2))
        let absent = try node(scope.defaults,{if case .generateIf = $0{return true};return false},ordinal:1)
        #expect(try SystemVerilogGenerateSelector.select(absent,in:scope,context:&run) == nil)
        let fallback = try root("module p; case(2) 1: begin: no end default: begin: yes end endcase endmodule",context:&run)
        #expect(try SystemVerilogGenerateSelector.select(node(fallback.defaults,{if case .generateCase = $0{return true};return false}),in:fallback,context:&run) == node(fallback.defaults,{if case .generateBlock = $0{return true};return false},ordinal:1))
    }
    @Test func laterMatchStillRequiresAValidConstantType() throws {
        guard #available(macOS 26.0, *) else { return }
        var run = try context()
        let scope = try root("module p; case(1) 1: begin: yes end missing: begin: no end endcase endmodule",context:&run)
        let selected = try node(scope.defaults,{if case .generateCase = $0{return true};return false})
        #expect(throws: LogicKernelError.self) { try SystemVerilogGenerateSelector.select(selected,in:scope,context:&run) }
    }
    @Test func signedAndExternalGenvarLoopsExecuteControlAndRetainValues() throws {
        guard #available(macOS 26.0, *) else { return }
        for declaration in ["for(genvar i=-2;i<2;i++)", "genvar i; for(i=-2;i<2;i+=1)"] {
            var run = try context()
            let scope = try root("module p; \(declaration) begin: g localparam A=i; end endmodule",context:&run)
            var control = try SystemVerilogStaticLoop.prepare(loop(scope),in:scope,context:&run)
            var iteration = try control.begin(context:&run)
            var values: [Int] = []
            var retained: SystemVerilogLoopIteration?
            while let current = iteration {
                let expected = try current.value.binaryInt(signed:true,context:&run)
                values.append(expected)
                let bodyScope = try current.scope.entering(current.body,context:&run)
                let entry = try #require(bodyScope.storage.entries.first { $0.value != nil })
                let constant = try #require(entry.value)
                #expect(try constant.value.binaryInt(signed:true,context:&run) == expected)
                if retained == nil {retained = current}
                iteration = try control.resume(afterBody:current,value:current.value,context:&run)
            }
            #expect(values == [-2,-1,0,1])
            #expect(try control.finalValue?.binaryInt(signed:true,context:&run) == 2)
            #expect(try retained?.value.binaryInt(signed:true,context:&run) == -2)
            #expect(throws: LogicKernelError.self) { try control.begin(context:&run) }
        }
    }
    @Test func generateInitializationUsesOuterScopeBeforeCreatingControl() throws {
        guard #available(macOS 26.0, *) else { return }
        var run = try context()
        let scope = try root("module p; parameter i=1; for(genvar i=i;i<2;i++) begin: g end endmodule",context:&run)
        var control = try SystemVerilogStaticLoop.prepare(loop(scope),in:scope,context:&run)
        let first = try required(control.begin(context:&run))
        #expect(try first.value.binaryInt(signed:true,context:&run) == 1)
        #expect(try control.resume(afterBody:first,value:first.value,context:&run) == nil)
    }
    @Test func generatedLocalparamCannotBeReusedAsExternalGenvar() throws {
        guard #available(macOS 26.0, *) else { return }
        var run = try context()
        let scope = try root("module p; genvar i; for(i=0;i<1;i++) begin: outer for(i=0;i<1;i++) begin: inner end end endmodule",context:&run)
        var outer = try SystemVerilogStaticLoop.prepare(loop(scope,ordinal:1),in:scope,context:&run)
        let current = try required(outer.begin(context:&run))
        let body = try current.scope.entering(current.body,context:&run)
        #expect(throws: LogicKernelError.self) {
            _ = try SystemVerilogStaticLoop.prepare(loop(scope),in:body,context:&run)
        }
    }
    @Test func generatedLocalparamSharesBodyScopeButFreshNestedGenvarCanShadow() throws {
        guard #available(macOS 26.0, *) else { return }
        var run = try context()
        let duplicate = try root("module p; for(genvar i=0;i<1;i++) begin: g localparam i=3; end endmodule",context:&run)
        var control = try SystemVerilogStaticLoop.prepare(loop(duplicate),in:duplicate,context:&run)
        let current = try required(control.begin(context:&run))
        #expect(throws: LogicKernelError.self) { _ = try current.scope.entering(current.body,context:&run) }
        let scope = try root("module p; for(genvar i=1;i<2;i++) begin: outer for(genvar i=i;i<2;i++) begin: inner end end endmodule",context:&run)
        var outer = try SystemVerilogStaticLoop.prepare(loop(scope,ordinal:1),in:scope,context:&run)
        let parent = try required(outer.begin(context:&run))
        let body = try parent.scope.entering(parent.body,context:&run)
        var inner = try SystemVerilogStaticLoop.prepare(loop(scope),in:body,context:&run)
        let nested = try required(inner.begin(context:&run))
        #expect(try nested.value.binaryInt(signed:true,context:&run) == 1)
        #expect(try inner.resume(afterBody:nested,value:nested.value,context:&run) == nil)
        let procedural = try root("module p; initial for(int i=0;i<1;i++) begin localparam i=3; end endmodule",context:&run)
        var procedure = try SystemVerilogStaticLoop.prepare(loop(procedural),in:procedural,context:&run)
        let statement = try required(procedure.begin(context:&run))
        let local = try statement.scope.entering(statement.body,context:&run)
        let entry = try #require(local.storage.entries.first)
        #expect(try entry.value?.value.binaryInt(signed:true,context:&run) == 3)
    }
    @Test func generateBodyCannotChangeItsFrozenControlValue() throws {
        guard #available(macOS 26.0, *) else { return }
        var run = try context()
        let scope = try root("module p; for(genvar i=0;i<2;i++) begin: g end endmodule",context:&run)
        var control = try SystemVerilogStaticLoop.prepare(loop(scope),in:scope,context:&run)
        let first = try required(control.begin(context:&run))
        #expect(throws: LogicKernelError.self) {
            try control.resume(afterBody:first,value:number(1,context:&run),context:&run)
        }
        #expect(control.finalValue == nil)
    }
    @Test func typedWideLoopWrapsAtItsDeclaredWidth() throws {
        guard #available(macOS 26.0, *) else { return }
        var run = try context()
        let scope = try root("module p; initial for(logic [64:0] i=65'h1ffffffffffffffff;i!=0;i++) begin end endmodule",context:&run)
        var control = try SystemVerilogStaticLoop.prepare(loop(scope),in:scope,context:&run)
        let current = try required(control.begin(context:&run))
        #expect(current.value.width.value == 65)
        #expect(try current.value.bit(at:64) == .one)
        let exhausted = try control.resume(afterBody:current,value:current.value,context:&run)
        #expect(exhausted == nil)
        #expect(try control.finalValue?.reducingBinary(.or,context:&run) == false)
    }
    @Test func compoundUpdateUsesCommonUnsignedContextAndBodyUpdatesAreExplicit() throws {
        guard #available(macOS 26.0, *) else { return }
        var run = try context()
        let scope = try root("module p; initial for(logic [7:0] i=0;i<100;i+=4'shf) begin end endmodule",context:&run)
        var control = try SystemVerilogStaticLoop.prepare(loop(scope),in:scope,context:&run)
        let first = try required(control.begin(context:&run))
        let next = try required(control.resume(afterBody:first,value:number(8,width:8,context:&run),context:&run))
        #expect(try next.value.binaryInt(signed:false,context:&run) == 23)
        #expect(throws: LogicKernelError.self) {try control.resume(afterBody:first,value:first.value,context:&run)}
    }
    @Test func lifecycleRejectsForeignIterationsAndBadBodyValues() throws {
        guard #available(macOS 26.0, *) else { return }
        for badWidth in [false,true] {
            var run = try context()
            let scope = try root("module p; for(genvar i=0;i<2;i++) begin: g end endmodule",context:&run)
            var one = try SystemVerilogStaticLoop.prepare(loop(scope),in:scope,context:&run)
            var two = try SystemVerilogStaticLoop.prepare(loop(scope),in:scope,context:&run)
            let first = try required(one.begin(context:&run)); let foreign = try required(two.begin(context:&run))
            if badWidth {
                #expect(throws: LogicKernelError.self) {try one.resume(afterBody:first,value:number(0,width:1,context:&run),context:&run)}
                #expect(throws: LogicKernelError.self) {try one.resume(afterBody:first,value:first.value,context:&run)}
            } else {
                #expect(throws: LogicKernelError.self) {try one.resume(afterBody:foreign,value:foreign.value,context:&run)}
                let advanced = try one.resume(afterBody:first,value:first.value,context:&run)
                #expect(advanced != nil)
            }
        }
    }
    @Test func initializationShadowingAndWrongControlTargetsFailAtSource() throws {
        guard #available(macOS 26.0, *) else { return }
        for text in ["parameter i=7; initial for(int i=i;i<2;i++) begin end", "genvar j; for(genvar i=0;i<2;j++) begin end", "parameter i=0; for(i=0;i<2;i++) begin end", "for(logic i=0;i<2;i++) begin end"] {
            var run = try context()
            let scope = try root("module p; \(text) endmodule",context:&run)
            do {
                var control = try SystemVerilogStaticLoop.prepare(loop(scope),in:scope,context:&run)
                _ = try control.begin(context:&run)
                Issue.record("Invalid loop was accepted")
            } catch let error as LogicKernelError {
                guard case .sourceFailure(_,let source,_) = error else {throw error}
                #expect(source.artifactID == scope.defaults.bindings.syntax.source.root.artifactID)
            }
        }
    }
    @Test func zeroIterationAndNegativeAssignmentStepPreserveFinalControlValues() throws {
        guard #available(macOS 26.0, *) else { return }
        for (initial,expected) in [("3",[3,1,-1]),("-3",[])] {
            var run = try context()
            let scope = try root("module p; for(genvar i=\(initial);i>=-1;i=i-2) begin: g end endmodule",context:&run)
            var control = try SystemVerilogStaticLoop.prepare(loop(scope),in:scope,context:&run)
            var iteration = try control.begin(context:&run)
            var observed: [Int] = []
            while let current = iteration {
                observed.append(try current.value.binaryInt(signed:true,context:&run))
                iteration = try control.resume(afterBody:current,value:current.value,context:&run)
            }
            #expect(observed == expected)
            #expect(try control.finalValue?.binaryInt(signed:true,context:&run) == -3)
        }
    }
    @Test func nonbinaryBodyValueAndSelectionStorageAdmissionFail() throws {
        guard #available(macOS 26.0, *) else { return }
        var run = try context()
        let scope = try root("module p; for(genvar i=0;i<2;i--) begin: g end case(1) 1: begin: yes end endcase endmodule",context:&run)
        var control = try SystemVerilogStaticLoop.prepare(loop(scope),in:scope,context:&run)
        let first = try required(control.begin(context:&run))
        let unknown = try LogicFourStateVector(repeating:.unknown,width:LogicBitWidth(32),context:&run)
        #expect(throws: LogicKernelError.self) {try control.resume(afterBody:first,value:unknown,context:&run)}
        #expect(control.finalValue == nil)
        let caseNode = try node(scope.defaults,{if case .generateCase = $0{return true};return false})
        var tight = LogicKernelContext(limits:try LogicKernelLimits(maximums:Dictionary(uniqueKeysWithValues:LogicResource.allCases.map {($0,$0 == .managedStorageBytes ? 1 : 1_000_000)})),control:LogicCancellationSource())
        #expect(throws: LogicKernelError.self) {try SystemVerilogGenerateSelector.select(caseNode,in:scope,context:&tight)}
        #expect(tight.usage[.allocationBytes] == 0)
    }
    @Test func nonterminationAndCancellationRemainFailures() throws {
        guard #available(macOS 26.0, *) else { return }
        var run = try context()
        let scope = try root("module p; for(genvar i=0;1;i=i) begin: g end endmodule",context:&run)
        var control = try SystemVerilogStaticLoop.prepare(loop(scope),in:scope,context:&run)
        var bounded = LogicKernelContext(limits: try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues: LogicResource.allCases.map {($0,$0 == .expansion ? 10 : 1_000_000)})),control:LogicCancellationSource())
        do {
            var iteration = try control.begin(context:&bounded)
            while let current = iteration {iteration = try control.resume(afterBody:current,value:current.value,context:&bounded)}
            Issue.record("Nontermination became successful exhaustion")
        } catch {
            guard case .resourceLimit(let resource,_,_) = error else {throw error}
            #expect(resource == .expansion)
            #expect(control.finalValue == nil)
        }
        var cancelledLoop = try SystemVerilogStaticLoop.prepare(loop(scope),in:scope,context:&run)
        let cancellation = LogicCancellationSource(); cancellation.cancel()
        var cancelled = LogicKernelContext(limits:run.limits,control:cancellation)
        #expect(throws: LogicKernelError.cancelled) {try cancelledLoop.begin(context:&cancelled)}
        #expect(cancelled.usage[.managedStorageBytes] == 0)
    }
}
