import Foundation
import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicDesignSerialization
import Synchronization
@testable import SystemVerilogFrontend

@Suite(.timeLimit(.minutes(1)))
struct ConstantEvaluationTests {
    private struct Control: LogicRunControlling { func checkpoint() throws(LogicKernelError) {} }
    @available(macOS 15.0, *)
    private final class Countdown: Sendable, LogicRunControlling {
        let remaining = Mutex(20)
        func checkpoint() throws(LogicKernelError) {
            let cancelled = remaining.withLock { count in count -= 1; return count <= 0 }
            if cancelled { throw .cancelled }
        }
    }
    private func context(_ maximum: UInt64 = 50_000_000) throws -> LogicKernelContext {
        LogicKernelContext(limits: try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
            LogicResource.allCases.map { ($0, maximum) })), control: Control())
    }
    @available(macOS 26.0, *)
    private func bind(_ text: String, context: inout LogicKernelContext) throws -> SystemVerilogParameterBindings {
        let bytes = Array(text.utf8)
        let source = try LogicSourceDocument(logicalName: "constants.sv", artifactID: ArtifactID(digest: ContentDigest(
            algorithm: .sha256, hexadecimalValue: LogicSourceDigest.sha256HexadecimalValue(of: Data(bytes))),
            byteCount: UInt64(bytes.count)), bytes: bytes, context: &context)
        let tokens = try SystemVerilogByteLexer().tokenize(source, maximumTokens: bytes.count + 1, context: &context)
        let capacity = max(100, bytes.count)
        let syntax = try SystemVerilogSyntaxParser.parse(tokens, limits: SystemVerilogSyntaxLimits(
            nodes: capacity, children: capacity, symbols: capacity, nesting: 100), context: &context)
        return try SystemVerilogParameterBinder.bind(syntax, module: syntax.child(at: syntax.modules.lowerBound), context: &context)
    }
    @available(macOS 26.0, *)
    private func defaults(_ body: String, context: inout LogicKernelContext) throws -> SystemVerilogParameterDefaults {
        try SystemVerilogConstantEvaluator.evaluate(bind("module m; " + body + " endmodule", context: &context), context: &context)
    }
    @available(macOS 26.0, *)
    private func check(_ defaults: SystemVerilogParameterDefaults, _ ordinal: Int, _ width: Int,
        _ signed: Bool, _ expected: Int, context: inout LogicKernelContext) throws {
        let constant = try defaults.value(forDeclaration: defaults.bindings.declaration(at: ordinal))
        #expect(constant.type.width.value == width && constant.type.isSigned == signed)
        #expect(try constant.value.binaryInt(signed: signed, context: &context) == expected)
    }

    @Test func assignmentContextPrecedesArithmeticAndSignConversion() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let result = try defaults("""
        parameter [8:0] SUM=8'hff+8'h01;
        parameter [15:0] PRODUCT=8'hff*8'hff;
        parameter [3:0] TRUNCATED=8'hf7;
        parameter signed [7:0] S=-4'sd1;
        parameter signed [7:0] U=4'hf;
        parameter [15:0] EXTEND=S;
        parameter [15:0] MIX=S+8'd0;
        parameter [15:0] CAST=$unsigned(S);
        parameter [15:0] BARRIER=$signed(4'hf);
        parameter signed SIGNONLY=4'hf;
        """, context: &run)
        for (i,w,s,v) in [(0,9,false,256),(1,16,false,65025),(2,4,false,7),
                          (3,8,true,-1),(4,8,true,15),(5,16,false,65535),
                          (6,16,false,255),(7,16,false,255),(8,16,false,65535),(9,4,true,-1)] {
            try check(result,i,w,s,v,context:&run)
        }
    }
    @Test func literalAndImplicitParameterTypesHaveSeparateSizingRules() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let result = try defaults("""
        parameter A='1;
        parameter signed B=2'b01;
        parameter int C=-1;
        parameter int unsigned D=32'hff;
        parameter logic E='1;
        parameter [8:0] F='1;
        parameter G={4'hf,'1,'0};
        parameter H=8'sh80 >>> 1;
        parameter I=8'sh80 >> 1;
        parameter J=1'b1 ? 8'shff : 16'sh0000;
        """, context: &run)
        for (i,w,s,v) in [(0,32,false,Int(UInt32.max)),(1,2,true,1),(2,32,true,-1),
                          (3,32,false,255),(4,1,false,1),(5,9,false,511),
                          (6,6,false,62),(7,8,true,-64),(8,8,true,64),(9,16,true,-1)] {
            try check(result,i,w,s,v,context:&run)
        }
    }
    @Test func packedIndexDirectionAndMultidimensionalSelectionsAreRetained() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let result = try defaults("""
        parameter [0:7] A=8'hb2;
        parameter B=A[0:3];
        parameter C=A[2 +: 3];
        parameter D=A[4 -: 3];
        parameter [1:0][0:3] M=8'ha5;
        parameter E=M[1];
        parameter F=M[1][0];
        parameter G=M[0][1:3];
        parameter [-2:-5] N=4'h9;
        parameter H=N[-2];
        """, context: &run)
        for (i,w,v) in [(0,8,178),(1,4,11),(2,3,6),(3,3,6),(4,8,165),(5,4,10),(6,1,1),(7,3,5),(8,4,9),(9,1,1)] {
            try check(result,i,w,false,v,context:&run)
        }
    }
    @Test func comparisonsReductionsAndLogicalOperatorsUseTheirOwnContexts() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let result = try defaults("""
        parameter A=8'shff < 8'sh01;
        parameter B=8'shff < 8'h01;
        parameter C=8'shff >= 8'sh01;
        parameter D=8'shff <= 8'shff;
        parameter E=8'hff === 8'hff;
        parameter F=8'hff !== 8'hff;
        parameter G=&8'hff;
        parameter H=~|8'h00;
        parameter I=^8'h07;
        parameter J=~^8'h07;
        parameter K=8'h02 && 8'h04;
        parameter L=!8'h00 || 8'h00;
        """, context: &run)
        for (i,v) in [1,0,0,1,1,0,1,1,1,0,1,1].enumerated() { try check(result,i,1,false,v,context:&run) }
    }
    @Test func inferredParametersFlattenRangesAndOnlyLiteralDefaultsAreUnsized() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let result = try defaults("""
        parameter [0:7] A=8'h80;
        parameter B=A;
        parameter C=B[0];
        parameter signed D='1;
        parameter signed E='h1_0000_0000;
        parameter F=~'0;
        parameter G=$unsigned('1);
        parameter H={+1};
        """,context:&run)
        try check(result,2,1,false,0,context:&run)
        try check(result,3,32,true,-1,context:&run)
        try check(result,4,32,true,0,context:&run)
        try check(result,5,1,false,1,context:&run)
        try check(result,6,1,false,1,context:&run)
        try check(result,7,32,false,1,context:&run)
    }
    @Test func wideValuesAndRepetitionDoNotNarrowToHostIntegers() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let result = try defaults("""
        parameter [256:0] A='1;
        parameter [256:0] B=A+257'd1;
        parameter C={129{2'b10}};
        parameter D=C[257:256];
        parameter E=A >> 129'd340282366920938463463374607431768211456;
        parameter F={2'b10,{0{3'b111}},2'b01};
        """, context: &run)
        let a = try result.value(forDeclaration: result.bindings.declaration(at:0))
        let b = try result.value(forDeclaration: result.bindings.declaration(at:1))
        #expect(a.type.width.value == 257 && b.type.width.value == 257)
        for bit in 0..<257 { #expect(try a.value.bit(at:bit) == .one); #expect(try b.value.bit(at:bit) == .zero) }
        let c = try result.value(forDeclaration: result.bindings.declaration(at:2))
        #expect(c.type.width.value == 258)
        for bit in 0..<258 { #expect(try c.value.bit(at:bit) == (bit % 2 == 0 ? .zero : .one)) }
        try check(result,3,2,false,2,context:&run)
        let e = try result.value(forDeclaration: result.bindings.declaration(at:4))
        #expect(try !e.value.reducingBinary(.or, context: &run))
        try check(result,5,4,false,9,context:&run)
    }
    @Test func sourceFailuresAndResourceExhaustionNeverPublishDefaults() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for (body, code) in [
            ("parameter A=4'bx;", "SV_SYNTHESIS_XZ_LITERAL"),
            ("parameter A={1,2'b00};", "SV_CONSTANT_CONCAT_SIZE"),
            ("parameter [7:0] A=0; parameter B=A[0:3];", "SV_CONSTANT_SELECT_DIRECTION"),
            ("parameter [7:0] A=0; parameter B=A[8];", "SV_SYNTHESIS_SELECT_X"),
            ("parameter A={-1{1'b1}};", "SV_CONSTANT_REPEAT_COUNT"),
            ("parameter A={0{1'b1}};", "SV_CONSTANT_EMPTY"),
            ("parameter A={{0{1'b1}}};", "SV_CONSTANT_EMPTY"),
            ("parameter A={1'b1,{0{1}}};", "SV_CONSTANT_CONCAT_SIZE"),
            ("parameter [7:0] A=0; parameter B=A[1 +: 0];", "SV_CONSTANT_SELECT_WIDTH")
        ] {
            var run = try context(); let bound = try bind("module m; " + body + " endmodule", context:&run)
            do { _ = try SystemVerilogConstantEvaluator.evaluate(bound,context:&run); Issue.record("Accepted invalid constant") }
            catch {
                guard case LogicKernelError.sourceFailure(let actual, let source, _) = error else { Issue.record("Lost source failure: \(error)"); continue }
                #expect(actual.rawValue == code && source.artifactID == bound.syntax.source.root.artifactID && !source.byteRange.isEmpty)
            }
        }
        var input = try context(); let bound = try bind("module m; parameter A={1000{1'b1}}; endmodule",context:&input)
        var limited = try context(1)
        #expect(throws: LogicKernelError.self) { try SystemVerilogConstantEvaluator.evaluate(bound,context:&limited) }
        #expect(limited.usage[.allocationBytes] == 0)
    }
    @Test func deepExpressionsAndIndependentSmallArithmeticAgree() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let deep = try defaults("parameter A=" + [String](repeating:"8'd1",count:1000).joined(separator:"+") + ";",context:&run)
        try check(deep,0,8,false,232,context:&run)
        for left in 0..<16 {
            for right in 0..<16 {
                let values = try defaults("parameter [8:0] A=4'd\(left)+4'd\(right); parameter [8:0] B=4'd\(left)*4'd\(right);",context:&run)
                try check(values,0,9,false,left+right,context:&run)
                try check(values,1,9,false,left*right,context:&run)
            }
        }
    }
    @Test func targetLayoutStorageAndMidEvaluationCancellationReleaseScratch() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var input = try context(); let empty = try bind("module m; endmodule",context:&input)
        let count = empty.syntax.nodeCount
        let published = UInt64(count * MemoryLayout<SystemVerilogConstant?>.stride)
        let scratch = UInt64(count * (MemoryLayout<SystemVerilogConstantEvaluator.Info?>.stride +
            2 * MemoryLayout<Int>.stride + 2 * MemoryLayout<SystemVerilogConstantEvaluator.Frame>.stride +
            MemoryLayout<LogicFourStateVector>.stride))
        var exact = try context(published + scratch)
        _ = try SystemVerilogConstantEvaluator.evaluate(empty,context:&exact)
        #expect(exact.usage.peakManagedStorageBytes == published + scratch)
        #expect(exact.usage[.managedStorageBytes] == published)
        var tight = try context(published + scratch - 1)
        #expect(throws: LogicKernelError.self) { try SystemVerilogConstantEvaluator.evaluate(empty,context:&tight) }
        #expect(tight.usage[.allocationBytes] == 0)
        let bound = try bind("module m; parameter A={1000{4'b1111}}; endmodule",context:&input)
        var cancelled = LogicKernelContext(limits: try LogicKernelLimits(maximums:Dictionary(uniqueKeysWithValues:
            LogicResource.allCases.map { ($0,UInt64(1_000_000)) })),control:Countdown())
        #expect(throws: LogicKernelError.cancelled) { try SystemVerilogConstantEvaluator.evaluate(bound,context:&cancelled) }
        let released = UInt64(bound.syntax.nodeCount * (MemoryLayout<SystemVerilogConstantEvaluator.Info?>.stride +
            2 * MemoryLayout<Int>.stride + 2 * MemoryLayout<SystemVerilogConstantEvaluator.Frame>.stride +
            MemoryLayout<LogicFourStateVector>.stride))
        // The literal decoder also releases its smaller temporary limb buffer.
        #expect(cancelled.usage[.allocationBytes] - cancelled.usage[.managedStorageBytes] >= released)
    }
    @Test func immutableDefaultsRetainInputsAcrossConcurrentBorrowers() async throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        let result = try { () throws -> SystemVerilogParameterDefaults in
            var run = try context(); return try defaults("parameter [128:0] A='1;",context:&run)
        }()
        let declaration = try result.bindings.declaration(at:0)
        try await withThrowingTaskGroup(of:Bool.self) { group in
            for _ in 0..<32 { group.addTask {
                let value = try result.value(forDeclaration:declaration)
                let retained = result.withValues { $0.count == result.bindings.syntax.nodeCount }
                return try retained && value.value.bit(at:128) == .one
            } }
            for try await valid in group { #expect(valid) }
        }
    }
}
