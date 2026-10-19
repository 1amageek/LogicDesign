import Foundation
import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicDesignSerialization
@testable import SystemVerilogFrontend

@Suite(.timeLimit(.minutes(1)))
struct ParameterOverrideTests {
    private struct Control: LogicRunControlling { func checkpoint() throws(LogicKernelError) {} }
    private func context(_ maximum: UInt64 = 10_000_000) throws -> LogicKernelContext {
        LogicKernelContext(limits: try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
            LogicResource.allCases.map { ($0, maximum) })), control: Control())
    }
    @available(macOS 26.0, *)
    private func bind(_ text: String, context: inout LogicKernelContext) throws -> SystemVerilogParameterBindings {
        let bytes = Array(text.utf8)
        let source = try LogicSourceDocument(logicalName: "override.sv", artifactID: ArtifactID(digest: ContentDigest(
            algorithm: .sha256, hexadecimalValue: LogicSourceDigest.sha256HexadecimalValue(of: Data(bytes))),
            byteCount: UInt64(bytes.count)), bytes: bytes, context: &context)
        let tokens = try SystemVerilogByteLexer().tokenize(source, maximumTokens: bytes.count + 1, context: &context)
        let syntax = try SystemVerilogSyntaxParser.parse(tokens, limits: SystemVerilogSyntaxLimits(
            nodes: bytes.count, children: bytes.count, symbols: bytes.count, nesting: 100), context: &context)
        return try SystemVerilogParameterBinder.bind(syntax, module: syntax.child(at: syntax.modules.lowerBound), context: &context)
    }
    @available(macOS 26.0, *)
    private func instance(_ defaults: SystemVerilogParameterDefaults) throws -> Int {
        let syntax = defaults.bindings.syntax
        for index in 0..<syntax.nodeCount { if case .instance = try syntax.node(at:index).kind { return index } }
        throw LogicKernelError.invalidInput("Expected an instance")
    }
    @available(macOS 26.0, *)
    private func expression(_ defaults: SystemVerilogParameterDefaults, ordinal: Int = 0,
        context: inout LogicKernelContext) throws -> SystemVerilogConstantExpression {
        guard case .instance(_, _, let parameters, _) = try defaults.bindings.syntax.node(at: instance(defaults)).kind,
              case .binding(_, let value?) = try defaults.bindings.syntax.node(at: defaults.bindings.syntax.child(at: parameters.lowerBound + ordinal)).kind else {
            throw LogicKernelError.invalidInput("Expected an instance override expression")
        }
        return try SystemVerilogConstantExpression.prepare(node: value, in: defaults, context: &context)
    }
    @Test func childWidthPropagatesIntoParentArithmeticAndDependentRanges() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let parent = try SystemVerilogConstantEvaluator.evaluate(bind("module p; parameter A=8'hff; child #(A+8'd1,4'd9) u(); endmodule", context:&run),context:&run)
        let child = try bind("module child; parameter [8:0] A=0; parameter W=2; localparam [W-1:0] MASK='1; endmodule",context:&run)
        let result = try SystemVerilogConstantEvaluator.evaluate(child, overrides:[
            SystemVerilogParameterOverride(declaration:child.declaration(at:0), in:child, expression:expression(parent,context:&run)),
            SystemVerilogParameterOverride(declaration:child.declaration(at:1), in:child, expression:expression(parent,ordinal:1,context:&run))
        ],context:&run)
        let a = try result.value(forDeclaration:child.declaration(at:0))
        let w = try result.value(forDeclaration:child.declaration(at:1))
        let mask = try result.value(forDeclaration:child.declaration(at:2))
        #expect(try a.value.binaryInt(signed:false,context:&run) == 256)
        #expect(w.type.width.value == 4)
        #expect(a.origin.artifactID == parent.bindings.syntax.source.root.artifactID)
        #expect(try a.origin == expression(parent,context:&run).origin)
        #expect(mask.origin.artifactID == child.syntax.source.root.artifactID)
        #expect(mask.type.width.value == 9)
        #expect(try mask.value.binaryInt(signed:false,context:&run) == 511)
    }
    @Test func implicitOverridesInferTheirOwnTypeAndExplicitTypesUseTheirOwnSign() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let parent = try SystemVerilogConstantEvaluator.evaluate(bind("module p; child #(4'shf,'1,4'hf) u(); endmodule",context:&run),context:&run)
        let child = try bind("module child; parameter A=32'd0; parameter signed B=2'd0; parameter signed [7:0] C=0; endmodule",context:&run)
        let supplied = try (0..<3).map { index in
            try SystemVerilogParameterOverride(declaration:child.declaration(at:index), in:child,
                expression:expression(parent,ordinal:index,context:&run))
        }
        let result = try SystemVerilogConstantEvaluator.evaluate(child,overrides:supplied,context:&run)
        let a = try result.value(forDeclaration:child.declaration(at:0))
        let b = try result.value(forDeclaration:child.declaration(at:1))
        let c = try result.value(forDeclaration:child.declaration(at:2))
        #expect(a.type.width.value == 4 && a.type.isSigned)
        #expect(try a.value.binaryInt(signed:true,context:&run) == -1)
        #expect(b.type.width.value == 32 && b.type.isSigned)
        #expect(try b.value.binaryInt(signed:true,context:&run) == -1)
        #expect(c.type.width.value == 8 && c.type.isSigned)
        #expect(try c.value.binaryInt(signed:true,context:&run) == 15)
    }
    @Test func overriddenDefaultsAreBoundButNotEvaluatedWithInvalidatedDimensions() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let parent = try SystemVerilogConstantEvaluator.evaluate(bind("module p; child #(0,8'd3) u(); endmodule",context:&run),context:&run)
        let child = try bind("module child; parameter W=1; parameter A={W{1'b1}}; localparam B=A+1'b1; endmodule",context:&run)
        let supplied = try (0..<2).map { index in
            try SystemVerilogParameterOverride(declaration:child.declaration(at:index), in:child,
                expression:expression(parent,ordinal:index,context:&run))
        }
        let result = try SystemVerilogConstantEvaluator.evaluate(child,overrides:supplied,context:&run)
        let b = try result.value(forDeclaration:child.declaration(at:2))
        #expect(b.type.width.value == 8)
        #expect(try b.value.binaryInt(signed:false,context:&run) == 4)
    }
    @Test func duplicateLocalForeignAndNonDeclarationTargetsAreRefused() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let parent = try SystemVerilogConstantEvaluator.evaluate(bind("module p; child #(1) u(); endmodule",context:&run),context:&run)
        let value = try expression(parent,context:&run)
        let text = "module child; parameter A=0; localparam B=1; endmodule"
        let child = try bind(text,context:&run); let foreign = try bind(text,context:&run)
        let regular = try SystemVerilogParameterOverride(declaration:child.declaration(at:0),in:child,expression:value)
        for (overrides,code) in [
            ([regular,regular], "SV_PARAMETER_DUPLICATE_OVERRIDE"),
            ([try SystemVerilogParameterOverride(declaration:child.declaration(at:1),in:child,expression:value)], "SV_PARAMETER_LOCAL_OVERRIDE")
        ] {
            do { _ = try SystemVerilogConstantEvaluator.evaluate(child,overrides:overrides,context:&run); Issue.record("Accepted invalid override") }
            catch {
                guard case LogicKernelError.sourceFailure(let actual,let source,_) = error else { Issue.record("Lost source failure"); continue }
                #expect(actual.rawValue == code && source.artifactID == child.syntax.source.root.artifactID)
            }
        }
        for supplied in [
            try SystemVerilogParameterOverride(declaration:foreign.declaration(at:0),in:foreign,expression:value),
            SystemVerilogParameterOverride(declaration:child.module,in:child,expression:value),
            SystemVerilogParameterOverride(declaration:-1,in:child,expression:value)
        ] {
            do { _ = try SystemVerilogConstantEvaluator.evaluate(child,overrides:[supplied],context:&run); Issue.record("Accepted foreign target") }
            catch { guard case LogicKernelError.invalidInput = error else { Issue.record("Wrong target failure"); continue } }
        }
    }
    @Test func expressionFailureReleasesItsWorkspaceAndRetainsExactParentSource() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let parent = try SystemVerilogConstantEvaluator.evaluate(bind("module p; child #(MISSING) u(); endmodule",context:&run),context:&run)
        let before = run.usage[.managedStorageBytes]
        do { _ = try expression(parent,context:&run); Issue.record("Accepted nonconstant expression") }
        catch {
            guard case LogicKernelError.sourceFailure(let code,let source,_) = error else { Issue.record("Lost parent source failure"); return }
            #expect(code.rawValue == "SV_CONSTANT_UNRESOLVED_NAME")
            #expect(source.artifactID == parent.bindings.syntax.source.root.artifactID)
            #expect(source.byteRange == 18..<25)
        }
        #expect(run.usage[.managedStorageBytes] == before)
    }
    @Test func expressionAdmissionChecksBudgetCancellationWidthAndModuleOwnership() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let parent = try SystemVerilogConstantEvaluator.evaluate(bind("module p; child #(8'd1) u(); endmodule module q; parameter Z=1; endmodule",context:&run),context:&run)
        let value = try expression(parent,context:&run)
        let scratch = UInt64(parent.bindings.syntax.nodeCount * SystemVerilogConstantEvaluator.workspaceStride)
        var tight = try context(scratch - 1)
        #expect(throws:LogicKernelError.self) { try expression(parent,context:&tight) }
        #expect(tight.usage[.allocationBytes] == 0)
        let control = LogicCancellationSource(); control.cancel()
        var cancelled = LogicKernelContext(limits:run.limits,control:control)
        #expect(throws:LogicKernelError.cancelled) { try value.evaluate(width:8,context:&cancelled) }
        #expect(cancelled.usage[.allocationBytes] == 0)
        #expect(throws:LogicKernelError.self) { try value.evaluate(width:0,context:&run) }
        let syntax = parent.bindings.syntax
        let foreign = try syntax.child(at:syntax.modules.upperBound - 1)
        #expect(throws:LogicKernelError.self) { try SystemVerilogConstantExpression.prepare(node:foreign,in:parent,context:&run) }
    }
    @Test func retainedExpressionEvaluatesIndependentlyAcrossNativeTasks() async throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        let value = try { () throws -> SystemVerilogConstantExpression in
            var run = try context()
            let parent = try SystemVerilogConstantEvaluator.evaluate(bind("module p; parameter A=8'hff; child #(A+8'd1) u(); endmodule",context:&run),context:&run)
            return try expression(parent,context:&run)
        }()
        try await withThrowingTaskGroup(of:Bool.self) { group in
            for _ in 0..<16 { group.addTask {
                var run = try context()
                let result = try value.evaluate(width:257,context:&run)
                return try result.width.value == 257 && result.binaryInt(signed:false,context:&run) == 256
            } }
            for try await correct in group { #expect(correct) }
        }
    }
    @Test func namedAssignmentsMatchAcrossDocumentsAndEscapedNames() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let parent = try SystemVerilogConstantEvaluator.evaluate(bind("module p; parameter A=8'hff; child #(.\\W (4'd9),.A(A+8'd1)) u(); endmodule",context:&run),context:&run)
        let child = try bind("module \\child #(parameter [8:0] A=0, parameter W=2); localparam [W-1:0] MASK='1; endmodule",context:&run)
        let result = try SystemVerilogInstanceParameterResolver.evaluate(instance:instance(parent),in:parent,child:child,context:&run)
        let a = try result.value(forDeclaration:child.declaration(at:0))
        let mask = try result.value(forDeclaration:child.declaration(at:2))
        #expect(try a.value.binaryInt(signed:false,context:&run) == 256)
        #expect(mask.type.width.value == 9)
        #expect(try mask.value.binaryInt(signed:false,context:&run) == 511)
    }
    @Test func orderedAndEmptyAssignmentsSkipLocalParametersAndRetainDefaults() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let child = try bind("module child #(localparam L=9, parameter A=1, localparam K=3, parameter B=2); parameter BODY=4; endmodule",context:&run)
        for assignments in [",8'd6", ".B(8'd6),.A()"] {
            let parent = try SystemVerilogConstantEvaluator.evaluate(bind("module p; child #(" + assignments + ") u(); endmodule",context:&run),context:&run)
            let result = try SystemVerilogInstanceParameterResolver.evaluate(instance:instance(parent),in:parent,child:child,context:&run)
            for (ordinal,expected) in [9,1,3,6,4].enumerated() {
                let value = try result.value(forDeclaration:child.declaration(at:ordinal))
                #expect(try value.value.binaryInt(signed:value.type.isSigned,context:&run) == expected)
            }
        }
    }
    @Test func instanceListFailuresRetainTheOriginalBindingSourceRange() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for (assignment,childText,code) in [
            (".A(),.A(1)","module child; parameter A=0; endmodule","SV_PARAMETER_DUPLICATE_OVERRIDE"),
            (".Q(1)","module child; parameter A=0; endmodule","SV_PARAMETER_UNKNOWN_OVERRIDE"),
            (".A(1),2","module child; parameter A=0,B=0; endmodule","SV_PARAMETER_MIXED_ASSIGNMENTS"),
            ("1,.B(2)","module child; parameter A=0,B=0; endmodule","SV_PARAMETER_MIXED_ASSIGNMENTS"),
            ("1,2","module child; parameter A=0; endmodule","SV_PARAMETER_EXCESS_ASSIGNMENTS"),
            (".BODY(1)","module child #(parameter A=0); parameter BODY=0; endmodule","SV_PARAMETER_LOCAL_OVERRIDE"),
            (".BODY()","module child #(); parameter BODY=0; endmodule","SV_PARAMETER_LOCAL_OVERRIDE"),
            ("1","module child #(); parameter BODY=0; endmodule","SV_PARAMETER_EXCESS_ASSIGNMENTS")
        ] {
            var run = try context()
            let parent = try SystemVerilogConstantEvaluator.evaluate(bind("module p; child #(" + assignment + ") u(); endmodule",context:&run),context:&run)
            let child = try bind(childText,context:&run)
            do { _ = try SystemVerilogInstanceParameterResolver.evaluate(instance:instance(parent),in:parent,child:child,context:&run); Issue.record("Accepted invalid parameter list") }
            catch {
                guard case LogicKernelError.sourceFailure(let actual,let source,_) = error else { Issue.record("Lost instance source failure: \(error)"); continue }
                #expect(actual.rawValue == code && source.artifactID == parent.bindings.syntax.source.root.artifactID)
                let entries = assignment.split(separator:",",omittingEmptySubsequences:false)
                let failedOrdinal = entries.count > 1 ? 1 : 0
                let prefix = "module p; child #(".utf8.count
                let start = prefix + (failedOrdinal == 1 ? entries[0].utf8.count + 1 : 0)
                #expect(source.byteRange == UInt64(start)..<UInt64(start + entries[failedOrdinal].utf8.count))
            }
        }
    }
    @Test func mismatchedModulesNestedScopeAndResourceFailureCannotPublishChildDefaults() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let parent = try SystemVerilogConstantEvaluator.evaluate(bind("module p; child #(1) u(); endmodule",context:&run),context:&run)
        let child = try bind("module child; parameter A=0; endmodule",context:&run)
        let other = try bind("module other; parameter A=0; endmodule",context:&run)
        #expect(throws:LogicKernelError.self) { try SystemVerilogInstanceParameterResolver.evaluate(instance:instance(parent),in:parent,child:other,context:&run) }
        let nested = try SystemVerilogConstantEvaluator.evaluate(bind("module p; if(1) begin : g child #(1) u(); end endmodule",context:&run),context:&run)
        #expect(throws:LogicKernelError.self) { try SystemVerilogInstanceParameterResolver.evaluate(instance:instance(nested),in:nested,child:child,context:&run) }
        var limited = try context(1)
        #expect(throws:LogicKernelError.self) { try SystemVerilogInstanceParameterResolver.evaluate(instance:instance(parent),in:parent,child:child,context:&limited) }
        #expect(limited.usage[.allocationBytes] == 0)
        let control = LogicCancellationSource(); control.cancel()
        var cancelled = LogicKernelContext(limits:run.limits,control:control)
        #expect(throws:LogicKernelError.cancelled) { try SystemVerilogInstanceParameterResolver.evaluate(instance:instance(parent),in:parent,child:child,context:&cancelled) }
        #expect(cancelled.usage[.allocationBytes] == 0)
    }
}
