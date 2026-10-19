import Foundation
import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicDesignSerialization
@testable import SystemVerilogFrontend

@Suite(.timeLimit(.minutes(1)))
struct ParameterBindingTests {
    private struct Control: LogicRunControlling { func checkpoint() throws(LogicKernelError) {} }
    private struct Cancelled: LogicRunControlling { func checkpoint() throws(LogicKernelError) { throw .cancelled } }
    private func context(control: any LogicRunControlling = Control(), storage: UInt64 = 50_000_000,
                         work: UInt64 = 50_000_000) throws -> LogicKernelContext {
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(50_000_000)) })
        limits[.managedStorageBytes] = storage; limits[.workUnits] = work
        return LogicKernelContext(limits: try LogicKernelLimits(maximums: limits), control: control)
    }
    @available(macOS 26.0, *)
    private func parse(_ text: String, context: inout LogicKernelContext) throws -> SystemVerilogSyntaxTree {
        let bytes = Array(text.utf8)
        let artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
            hexadecimalValue: LogicSourceDigest.sha256HexadecimalValue(of: Data(bytes))), byteCount: UInt64(bytes.count))
        let source = try LogicSourceDocument(logicalName: "parameters.sv", artifactID: artifact, bytes: bytes, context: &context)
        let tokens = try SystemVerilogByteLexer().tokenize(source, maximumTokens: bytes.count + 1, context: &context)
        let capacity = max(100, bytes.count)
        return try SystemVerilogSyntaxParser.parse(tokens, limits: SystemVerilogSyntaxLimits(
            nodes: capacity, children: capacity, symbols: capacity, nesting: 100), context: &context)
    }
    @available(macOS 26.0, *)
    private func name(_ symbol: Int, syntax: SystemVerilogSyntaxTree) throws -> String {
        let range = try syntax.symbolRange(at: symbol)
        return syntax.source.withBytes { bytes in
            var result: [UInt8] = []
            for index in range { result.append(bytes[index]) }
            return String(decoding: result, as: UTF8.self)
        }
    }
    private func parameterName(_ declaration: Int, syntax: SystemVerilogSyntaxTree) throws -> Int {
        guard case .declaration(_, let name, _, _) = try syntax.node(at: declaration).kind else {
            throw LogicKernelError.invalidModel("Missing parameter declaration")
        }
        return name
    }

    @Test func headerBodyOrderAndModuleNamespacesRemainDistinct() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        let tree = try parse("""
        module first #(parameter W=129, localparam D=W+1);
          parameter signed [W-1:0] MASK='1;
          localparam TOTAL=D+W;
        endmodule
        module second #(parameter W=8, D=W*2); endmodule
        """, context: &context)
        let first = try SystemVerilogParameterBinder.bind(tree, module: tree.child(at: tree.modules.lowerBound), context: &context)
        let second = try SystemVerilogParameterBinder.bind(tree, module: tree.child(at: tree.modules.lowerBound + 1), context: &context)
        var names: [String] = []
        for ordinal in 0..<first.count {
            names.append(try name(parameterName(first.declaration(at: ordinal), syntax: tree), syntax: tree))
        }
        #expect(names == ["W", "D", "MASK", "TOTAL"] && second.count == 2)
        let firstW = try first.declaration(at: 0); let secondW = try second.declaration(at: 0)
        let firstD = try first.declaration(at: 1)
        #expect(firstW != secondW)
        let symbol = try parameterName(firstW, syntax: tree)
        #expect(try first.declaration(named: symbol) == firstW)
        #expect(try second.declaration(named: symbol) == secondW)
        var firstReferences = 0; var secondReferences = 0
        for index in 0..<tree.nodeCount {
            if let target = try first.declaration(forReference: index) {
                firstReferences += 1; #expect(target == firstW || target == firstD)
            }
            if let target = try second.declaration(forReference: index) {
                secondReferences += 1; #expect(target == secondW)
            }
        }
        #expect(firstReferences == 4 && secondReferences == 1)
    }

    @Test func packedDimensionsAndEveryExpressionOperandAreBound() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        let tree = try parse("""
        module m #(parameter A=8'ha5, N=2);
        localparam [A:0][N:0] B=~(A+N);
        localparam C=(A>N)?$signed(A<<N):$unsigned(A>>N);
        localparam D={N{A[N +: 1]}};
        localparam E={A[7:0],N,A[N],A[7 -: N]};
        localparam F=&A || !N;
        wire sink; assign sink=A;
        endmodule
        """, context: &context)
        let bindings = try SystemVerilogParameterBinder.bind(tree, module: tree.child(at: tree.modules.lowerBound), context: &context)
        #expect(bindings.count == 7)
        let a = try bindings.declaration(at: 0); let n = try bindings.declaration(at: 1)
        var references = 0; var outside = 0
        for index in 0..<tree.nodeCount {
            if case .identifier = try tree.node(at: index).kind {
                if let target = try bindings.declaration(forReference: index) {
                    references += 1; #expect(target == a || target == n)
                } else { outside += 1 }
            }
        }
        #expect(references == 21 && outside == 2)
    }

    @Test func transparentRegionsAndNestedScopesHaveDifferentOwners() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        let tree = try parse("""
        module m #(parameter A=1);
          generate localparam B=A+1;
            if (A) begin : selected localparam A=MISSING; end
            for (genvar i=0; i<A; i++) begin : bits localparam A=i; end
          endgenerate
          always_comb begin localparam A=UNKNOWN; q=A; end
          localparam C=B+1;
        endmodule
        """, context: &context)
        let bindings = try SystemVerilogParameterBinder.bind(tree, module: tree.child(at: tree.modules.lowerBound), context: &context)
        var names: [String] = []
        for index in 0..<bindings.count {
            names.append(try name(parameterName(bindings.declaration(at: index), syntax: tree), syntax: tree))
        }
        #expect(names == ["A", "B", "C"])
        #expect(bindings.withBindings { declarations, references, _ in
            guard declarations.count == 3 else { return false }
            var first = false; var second = false
            for index in references.indices {
                first = first || references[index] == declarations[0]
                second = second || references[index] == declarations[1]
            }
            return first && second
        })
    }

    @Test func unresolvedDuplicateSelfAndForwardNamesFailAtTheirSource() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for (text, code, offending) in [
            ("module m; parameter A=MISSING; endmodule", "SV_PARAMETER_UNRESOLVED_NAME", "MISSING"),
            ("module m(input wire x); parameter UNUSED=x; endmodule", "SV_PARAMETER_UNRESOLVED_NAME", "x"),
            ("module m; parameter A=A; endmodule", "SV_PARAMETER_SELF_REFERENCE", "A"),
            ("module m; parameter [A:0] A=1; endmodule", "SV_PARAMETER_SELF_REFERENCE", "A"),
            ("module m; parameter A=B, B=1; endmodule", "SV_PARAMETER_BEFORE_DECLARATION", "B"),
            ("module m; parameter A=B, B=A; endmodule", "SV_PARAMETER_BEFORE_DECLARATION", "B"),
            ("module m; parameter [B:0] A=1; parameter B=2; endmodule", "SV_PARAMETER_BEFORE_DECLARATION", "B"),
            ("module m; parameter A=1; localparam A=2; endmodule", "SV_PARAMETER_DUPLICATE", "A"),
            ("module m; parameter A=1; localparam \\A =2; endmodule", "SV_PARAMETER_DUPLICATE", "A"),
            ("module m; parameter A=1 ? 0 : MISSING; endmodule", "SV_PARAMETER_UNRESOLVED_NAME", "MISSING")
        ] {
            var context = try context(); let tree = try parse(text, context: &context)
            do {
                _ = try SystemVerilogParameterBinder.bind(tree, module: tree.child(at: tree.modules.lowerBound), context: &context)
                Issue.record("Accepted invalid parameter reference: \(text)")
            } catch {
                guard case LogicKernelError.sourceFailure(let actual, let range, _) = error else {
                    Issue.record("Lost source failure: \(error)"); continue
                }
                #expect(actual.rawValue == code && range.artifactID == tree.source.root.artifactID)
                let bytes = Array(text.utf8)
                let spelling = String(decoding: bytes[Int(range.byteRange.lowerBound)..<Int(range.byteRange.upperBound)], as: UTF8.self)
                #expect(spelling.contains(offending))
                if code != "SV_PARAMETER_DUPLICATE" { #expect(spelling == offending) }
            }
        }
    }

    @Test func emptyScopesCheckedLookupAndTypedBorrowRetainTheirOwners() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context(); let tree = try parse("module empty; endmodule", context: &context)
        let bindings = try SystemVerilogParameterBinder.bind(tree, module: tree.child(at: tree.modules.lowerBound), context: &context)
        #expect(bindings.count == 0 && bindings.syntax.source.root.artifactID == tree.source.root.artifactID)
        #expect(bindings.withBindings { $0.isEmpty && $1.count == tree.nodeCount && $2.count == tree.symbolCount })
        #expect(try bindings.declaration(named: 0) == nil)
        #expect(try bindings.declaration(forReference: 0) == nil)
        #expect(throws: LogicKernelError.self) { try bindings.declaration(at: 0) }
        #expect(throws: LogicKernelError.self) { try bindings.declaration(named: -1) }
        #expect(throws: LogicKernelError.self) { try bindings.declaration(forReference: tree.nodeCount) }
        #expect(throws: LogicKernelError.self) { try SystemVerilogParameterBinder.bind(tree, module: -1, context: &context) }
        enum BorrowFailure: Error { case expected }
        #expect(throws: BorrowFailure.expected) {
            try bindings.withBindings { (_, _, _) throws(BorrowFailure) in throw .expected }
        }
    }

    @Test func storageIsAdmittedBeforeAllocationAndScratchReleasesOnFailure() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var input = try context(); let tree = try parse("module m #(parameter A=1, B=A+A); endmodule", context: &input)
        let module = try tree.child(at: tree.modules.lowerBound)
        let published = UInt64((2 * tree.nodeCount + tree.symbolCount) * MemoryLayout<Int>.stride)
        let scratch = UInt64(tree.nodeCount * (MemoryLayout<Int>.stride + MemoryLayout<UInt8>.stride))
        var success = try context(storage: published + scratch)
        _ = try SystemVerilogParameterBinder.bind(tree, module: module, context: &success)
        #expect(success.usage.peakManagedStorageBytes == published + scratch)
        #expect(success.usage[.managedStorageBytes] == published)
        var noStorage = try context(storage: published + scratch - 1)
        #expect(throws: LogicKernelError.self) { try SystemVerilogParameterBinder.bind(tree, module: module, context: &noStorage) }
        #expect(noStorage.usage[.allocationBytes] == 0)
        var cancelled = try context(control: Cancelled())
        #expect(throws: LogicKernelError.cancelled) { try SystemVerilogParameterBinder.bind(tree, module: module, context: &cancelled) }
        #expect(cancelled.usage[.allocationBytes] == 0)
        var exhausted = try context(work: 1)
        #expect(throws: LogicKernelError.resourceLimit(resource: .workUnits, limit: 1, requested: 2)) {
            try SystemVerilogParameterBinder.bind(tree, module: module, context: &exhausted)
        }
        #expect(exhausted.usage[.managedStorageBytes] == published)
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(50_000_000)) })
        limits[.edges] = 1
        var edges = LogicKernelContext(limits: try LogicKernelLimits(maximums: limits), control: Control())
        #expect(throws: LogicKernelError.resourceLimit(resource: .edges, limit: 1, requested: 2)) {
            try SystemVerilogParameterBinder.bind(tree, module: module, context: &edges)
        }
        #expect(edges.usage[.managedStorageBytes] == published)
    }

    @Test func longDependencyChainsUseFlatBoundedTraversal() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var text = "module m; parameter P0=1;"
        for index in 1..<1000 { text += " localparam P\(index)=P\(index - 1)+1;" }
        text += " endmodule"
        var context = try context(); let tree = try parse(text, context: &context)
        let bindings = try SystemVerilogParameterBinder.bind(tree, module: tree.child(at: tree.modules.lowerBound), context: &context)
        #expect(bindings.count == 1000)
        var edges = 0
        for node in 0..<tree.nodeCount { if try bindings.declaration(forReference: node) != nil { edges += 1 } }
        #expect(edges == 999)
        let deep = "module deep; parameter A=1, B=" + [String](repeating: "A", count: 1000).joined(separator: "+") + "; endmodule"
        let deepTree = try parse(deep, context: &context)
        let deepBindings = try SystemVerilogParameterBinder.bind(deepTree,
            module: deepTree.child(at: deepTree.modules.lowerBound), context: &context)
        var deepEdges = 0
        for node in 0..<deepTree.nodeCount { if try deepBindings.declaration(forReference: node) != nil { deepEdges += 1 } }
        #expect(deepEdges == 1000)
    }

    @Test func immutableBindingsRetainExactSourceAcrossConcurrentReaders() async throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        let bindings = try { () throws -> SystemVerilogParameterBindings in
            var context = try context()
            let tree = try parse("module m #(parameter \\日本語 =1, Q=\\日本語 ); endmodule", context: &context)
            return try SystemVerilogParameterBinder.bind(tree, module: tree.child(at: tree.modules.lowerBound), context: &context)
        }()
        #expect(try name(parameterName(bindings.declaration(at: 0), syntax: bindings.syntax), syntax: bindings.syntax) == "日本語")
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    let first = try bindings.declaration(at: 0)
                    return bindings.withBindings { declarations, references, _ in
                        guard declarations.count == 2 && declarations[0] == first else { return false }
                        var found = 0
                        for index in references.indices { if references[index] == first { found += 1 } }
                        return found == 1
                    }
                }
            }
            for try await valid in group { #expect(valid) }
        }
    }
}
