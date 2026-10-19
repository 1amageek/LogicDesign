import Foundation
import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicDesignSerialization
@testable import SystemVerilogFrontend

@Suite(.timeLimit(.minutes(1)))
struct PortableSyntaxTests {
    private struct Control: LogicRunControlling { func checkpoint() throws(LogicKernelError) {} }
    private struct Cancelled: LogicRunControlling { func checkpoint() throws(LogicKernelError) { throw .cancelled } }
    private func context(control: any LogicRunControlling = Control(), work: UInt64 = 10_000_000,
                         storage: UInt64 = 10_000_000) throws -> LogicKernelContext {
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(10_000_000)) })
        limits[.workUnits] = work; limits[.managedStorageBytes] = storage
        return LogicKernelContext(limits: try LogicKernelLimits(maximums: limits), control: control)
    }
    @available(macOS 26.0, *)
    private func tokens(_ text: String, context: inout LogicKernelContext) throws -> SystemVerilogTokenStream {
        let bytes = Array(text.utf8)
        let artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
            hexadecimalValue: LogicSourceDigest.sha256HexadecimalValue(of: Data(bytes))), byteCount: UInt64(bytes.count))
        let source = try LogicSourceDocument(logicalName: "syntax.sv", artifactID: artifact, bytes: bytes, context: &context)
        return try SystemVerilogByteLexer().tokenize(source, maximumTokens: max(1, bytes.count + 1), context: &context)
    }
    @available(macOS 26.0, *)
    private func parse(_ text: String, context: inout LogicKernelContext, nodes: Int = 2000, children: Int = 2000,
                       symbols: Int = 200, nesting: Int = 100) throws -> SystemVerilogSyntaxTree {
        let stream = try tokens(text, context: &context)
        return try SystemVerilogSyntaxParser.parse(stream, limits: SystemVerilogSyntaxLimits(
            nodes: nodes, children: children, symbols: symbols, nesting: nesting), context: &context)
    }
    @available(macOS 26.0, *)
    private func spelling(_ range: Range<Int>, tree: SystemVerilogSyntaxTree) -> String {
        tree.source.withBytes { bytes in
            var spelling: [UInt8] = []; spelling.reserveCapacity(range.count)
            for index in range { spelling.append(bytes[index]) }
            return String(decoding: spelling, as: UTF8.self)
        }
    }
    @available(macOS 26.0, *)
    private func name(_ index: Int, tree: SystemVerilogSyntaxTree) throws -> String {
        spelling(try tree.symbolRange(at: index), tree: tree)
    }
    @available(macOS 26.0, *)
    private func shape(_ index: Int, tree: SystemVerilogSyntaxTree) throws -> String {
        let node = try tree.node(at: index)
        switch node.kind {
        case .identifier(let symbol): return try name(symbol, tree: tree)
        case .literal: return spelling(node.byteRange, tree: tree)
        case .unary(let op, let value): return "\(op)(\(try shape(value, tree: tree)))"
        case .binary(let op, let lhs, let rhs): return "\(op)(\(try shape(lhs, tree: tree)),\(try shape(rhs, tree: tree)))"
        case .conditional(let condition, let then, let elseBody):
            return "?(\(try shape(condition, tree: tree)),\(try shape(then, tree: tree)),\(try shape(elseBody, tree: tree)))"
        default: return "other"
        }
    }

    @Test func operatorPrecedenceAssociativityAndNonblockingLvalueAreDistinct() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        let tree = try parse("""
        module top;
        assign y = a | b ^ c & d == e < f << g + h * -i ? j : k ? l : m;
        assign z = a - b - c;
        always_ff @(posedge clk) q[3:0] <= a <= b;
        endmodule
        """, context: &context)
        var shapes: [String] = []; var timings: [SystemVerilogSyntaxNode.Assignment] = []
        for index in 0..<tree.nodeCount {
            if case .assignment(let timing, _, let value) = try tree.node(at: index).kind, let value {
                shapes.append(try shape(value, tree: tree)); timings.append(timing)
            }
        }
        #expect(shapes == ["?(or(a,xor(b,and(c,equal(d,less(e,shiftLeft(f,add(g,multiply(h,minus(i))))))))),j,?(k,l,m))",
                           "subtract(subtract(a,b),c)", "lessEqual(a,b)"])
        #expect(timings == [.blocking, .blocking, .nonBlocking])
    }

    @Test func numericConditionalTokensDoNotAbsorbQuestionMarks() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        let tree = try parse("module top; assign a=1?2:3; assign b='0?1:'1; endmodule", context: &context)
        var shapes: [String] = []
        for index in 0..<tree.nodeCount {
            if case .assignment(_, _, let value) = try tree.node(at: index).kind, let value {
                shapes.append(try shape(value, tree: tree))
            }
        }
        #expect(shapes == ["?(1,2,3)", "?('0,1,'1)"])
        let stream = try tokens("4'b1?0 4'hf? 'x?1:0 12abc", context: &context)
        let spellings: [String] = stream.withTokens { tokens in
            stream.source.withBytes { bytes in
                var values: [String] = []
                for index in tokens.indices {
                    var value: [UInt8] = []
                    for offset in tokens[index].byteRange { value.append(bytes[offset]) }
                    values.append(String(decoding: value, as: UTF8.self))
                }
                return values
            }
        }
        #expect(spellings == ["4'b1?0", "4'hf?", "'x", "?", "1", ":", "0", "12", "abc", ""])
    }

    @Test func hierarchyParametersPackedTypesAndStaticGenerateRetainBindings() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        let tree = try parse("""
        module child #(parameter W=8, D=W+1)(input logic signed [W-1:0] a,b, output [0:D-1] y);
        assign y = {a, b[0 +: 1]};
        endmodule : child
        module top(a,y);
        parameter W=129; localparam signed [W:0] MASK = 130 'sH 1;
        input [W-1:0] a; output [W-1:0] y; genvar i;
        generate
          if (W > 1) begin : wide
            for (genvar j=0; j<W; j++) begin : bits
              child #(.W(1),.D(1)) u(.a(a[j]),.b('0),.y(y[j]));
            end : bits
          end : wide else begin : narrow
            child #(1,1) u(a,'0,y);
          end
        endgenerate
        endmodule
        """, context: &context)
        #expect(tree.modules.count == 2)
        guard case .module(let childName, let parameters, let ports, _, _) = try tree.node(at: tree.child(at: tree.modules.lowerBound)).kind else {
            Issue.record("Missing module"); return
        }
        #expect(try name(childName, tree: tree) == "child")
        #expect(parameters.count == 2 && ports.count == 3)
        guard case .port(.input, _, let firstType, _) = try tree.node(at: tree.child(at: ports.lowerBound)).kind,
              case .port(.input, _, let secondType, _) = try tree.node(at: tree.child(at: ports.lowerBound + 1)).kind else {
            Issue.record("Lost inherited ANSI port direction"); return
        }
        #expect(firstType != nil && firstType == secondType)
        var instances = 0; var loops = 0; var namedBindings = 0; var literals: [String] = []
        for index in 0..<tree.nodeCount {
            switch try tree.node(at: index).kind {
            case .instance: instances += 1
            case .generateFor: loops += 1
            case .binding(let name, _): if name != nil { namedBindings += 1 }
            case .literal: literals.append(spelling(try tree.node(at: index).byteRange, tree: tree))
            default: break
            }
        }
        #expect(instances == 2 && loops == 1 && namedBindings == 5)
        #expect(literals.contains("130 'sH 1"))
    }

    @Test func orderedBlocksEventsCaseLoopsAndSelectionsArePreserved() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        let tree = try parse("""
        module top(input clk, reset_n, en, input [7:0] a, output logic [7:0] q);
        always_ff @(negedge reset_n or posedge clk) begin : update
          if (!reset_n) q <= '0;
          else if (en) begin
            for (int i=0; i<8; ++i) q[i] <= a[7-i];
            case (a[1:0])
              0,1: q <= {2{a[3:0]}};
              1: q <= a[7 -: 8];
              default q <= $unsigned($signed(a));
            endcase
          end
        end : update
        always_comb begin logic [7:0] t; t = a; t = t + 1; end
        always_latch if (en) q = a;
        always @(*) q = a;
        endmodule
        """, context: &context)
        var events: [SystemVerilogSyntaxNode.Edge] = []; var blocks = 0; var loops = 0
        var caseArms: [Int] = []; var assignments = 0; var allSensitivity = 0
        var selects: [SystemVerilogSyntaxNode.Selection] = []; var repeated = 0
        for index in 0..<tree.nodeCount {
            switch try tree.node(at: index).kind {
            case .event(let edge, _): events.append(edge)
            case .block: blocks += 1
            case .forStatement: loops += 1
            case .caseArm(let matches, _): caseArms.append(matches.count)
            case .assignment: assignments += 1
            case .sensitivity(let all, _): if all { allSensitivity += 1 }
            case .select(let selection, _, _, _): selects.append(selection)
            case .repeated: repeated += 1
            default: break
            }
        }
        #expect(events == [.falling, .rising])
        #expect(blocks == 3 && loops == 1 && caseArms == [2, 1, 0] && repeated == 1)
        #expect(assignments == 10 && allSensitivity == 1)
        #expect(selects.contains(.bit) && selects.contains(.range) && selects.contains(.indexedDown))
    }

    @Test func generateCasePortStorageAndEmptyConnectionsKeepSemanticDistinctions() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        let tree = try parse("""
        module top(output wire logic a, output logic b, output [3:0] c, output var d);
        case (1)
          0,1: begin : x child u(.a(), .b(a)); end
          default: child u(a, , );
        endcase
        endmodule
        """, context: &context)
        var types: [(SystemVerilogSyntaxNode.Storage, Bool)] = []; var generated = 0; var disconnected = 0
        for index in 0..<tree.nodeCount {
            switch try tree.node(at: index).kind {
            case .type(_, _, _, let storage, let explicitBase): types.append((storage, explicitBase))
            case .generateCase: generated += 1
            case .binding(_, let value): if value == nil { disconnected += 1 }
            default: break
            }
        }
        #expect(types.count == 4)
        #expect(types[0].0 == .net && types[0].1)
        #expect(types[1].0 == .unspecified && types[1].1)
        #expect(types[2].0 == .unspecified && !types[2].1)
        #expect(types[3].0 == .variable && !types[3].1)
        #expect(generated == 1 && disconnected == 3)
    }

    @Test func escapedNamesAreExactInternedAndCannotTurnIntoKeywords() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        let tree = try parse("module \\module ; logic a; logic \\日本語 ; assign a = \\a ; assign \\日本語 = a; endmodule", context: &context)
        #expect(tree.symbolCount == 3)
        #expect(try name(0, tree: tree) == "module")
        #expect(try name(2, tree: tree) == "日本語")
        #expect(throws: LogicKernelError.self) { try tree.node(at: -1) }
        #expect(throws: LogicKernelError.self) { try tree.child(at: 1000) }
        #expect(throws: LogicKernelError.self) { try tree.symbolRange(at: 3) }
        let empty = try parse("", context: &context)
        #expect(empty.withTables { $0.isEmpty && $1.isEmpty && $2.isEmpty })
    }

    @Test func malformedAndUnsupportedInputAlwaysHasExactSourceFailure() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for text in ["module module; endmodule", "package p; endpackage", "interface i; endinterface",
                     "module t; logic a[8]; endmodule", "module t; int [3:0] a; endmodule", "module t; assign a=b/c; endmodule",
                     "module t; assign a=b%c; endmodule", "module t; assign a=b**c; endmodule",
                     "module t; always_comb casex(a) default: a=0; endcase endmodule",
                     "module t; always_comb casez(a) default: a=0; endcase endmodule",
                     "module t; always_comb case(a) default: a=0; default: a=1; endcase endmodule",
                     "module t; always_ff @(posedge c) q <= ; endmodule",
                     "module t; assign a={}; endmodule", "module t; always_comb begin a=1; end : bad endmodule",
                     "module t; endmodule : other", "module t;", "module t; assign a=f(b); endmodule",
                     "module t; `include \"missing.svh\" endmodule", "module t; always_comb a=1; garbage endmodule"] {
            var context = try context()
            let stream = try tokens(text, context: &context)
            do {
                _ = try SystemVerilogSyntaxParser.parse(stream, limits: SystemVerilogSyntaxLimits(nodes: 2000,
                    children: 2000, symbols: 200, nesting: 100), context: &context)
                Issue.record("Accepted malformed or unsupported source: \(text)")
            } catch {
                guard case LogicKernelError.sourceFailure(_, let range, _) = error else { Issue.record("Lost located failure: \(error)"); continue }
                #expect(range.artifactID == stream.source.root.artifactID)
                #expect(range.byteRange.upperBound <= UInt64(stream.source.byteCount))
            }
        }
    }

    @Test func systemNamesCannotBecomeOrdinaryIdentifiers() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for text in ["module $top; endmodule", "module t; logic $time; endmodule",
                     "module t; assign q=$time; endmodule", "module t; $child u(); endmodule"] {
            var context = try context()
            do {
                _ = try parse(text, context: &context)
                Issue.record("Accepted a system name as an ordinary identifier")
            } catch {
                guard case LogicKernelError.sourceFailure(let code, let range, _) = error else {
                    Issue.record("Lost located system-name failure"); continue
                }
                #expect(code.rawValue == "SV_SYNTAX_SYSTEM_IDENTIFIER")
                #expect(text.utf8[text.utf8.index(text.utf8.startIndex, offsetBy: Int(range.byteRange.lowerBound))] == 36)
            }
        }
        var context = try context()
        let tree = try parse("module a$b; logic \\$time ; assign q=\\$time ; assign r=$signed(q); endmodule", context: &context)
        #expect(try name(0, tree: tree) == "a$b")
        var names: [String] = []; var casts = 0
        for index in 0..<tree.nodeCount {
            switch try tree.node(at: index).kind {
            case .identifier(let symbol): names.append(try name(symbol, tree: tree))
            case .signedCast: casts += 1
            default: break
            }
        }
        #expect(names.contains("$time") && casts == 1)
    }

    @Test func mismatchedEndLabelsLocateTheOffendingLabel() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for text in ["module t; endmodule : wrong", "module t; always_comb begin : good q=0; end : wrong endmodule",
                     "module t; if (1) begin : good wire q; end : wrong endmodule"] {
            var context = try context()
            let stream = try tokens(text, context: &context)
            let label = try #require(text.range(of: "wrong"))
            let offset = text[..<label.lowerBound].utf8.count
            do {
                _ = try SystemVerilogSyntaxParser.parse(stream, limits: SystemVerilogSyntaxLimits(
                    nodes: 200, children: 200, symbols: 20, nesting: 30), context: &context)
                Issue.record("Accepted a mismatched end label")
            } catch {
                guard case LogicKernelError.sourceFailure(let code, let range, _) = error else {
                    Issue.record("Lost source failure"); continue
                }
                #expect(code.rawValue == "SV_SYNTAX_END_LABEL")
                #expect(range.artifactID == stream.source.root.artifactID)
                #expect(range.byteRange == UInt64(offset)..<UInt64(offset + 5))
            }
        }
    }

    @Test func syntaxLimitsCancellationAndTemporaryStorageAreEnforced() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        let stream = try tokens("module top(input a, output y); assign y=((((a)))); endmodule", context: &context)
        let normal = try SystemVerilogSyntaxLimits(nodes: 100, children: 100, symbols: 20, nesting: 30)
        for limits in [try SystemVerilogSyntaxLimits(nodes: 1, children: 100, symbols: 20, nesting: 30),
                       try SystemVerilogSyntaxLimits(nodes: 100, children: 1, symbols: 20, nesting: 30),
                       try SystemVerilogSyntaxLimits(nodes: 100, children: 100, symbols: 1, nesting: 30),
                       try SystemVerilogSyntaxLimits(nodes: 100, children: 100, symbols: 20, nesting: 2)] {
            #expect(throws: LogicKernelError.self) { try SystemVerilogSyntaxParser.parse(stream, limits: limits, context: &context) }
        }
        var cancelled = try self.context(control: Cancelled())
        #expect(throws: LogicKernelError.cancelled) { try SystemVerilogSyntaxParser.parse(stream, limits: normal, context: &cancelled) }
        var exhausted = try self.context(work: 1)
        #expect(throws: LogicKernelError.self) { try SystemVerilogSyntaxParser.parse(stream, limits: normal, context: &exhausted) }
        var noStorage = try self.context(storage: 1)
        #expect(throws: LogicKernelError.self) { try SystemVerilogSyntaxParser.parse(stream, limits: normal, context: &noStorage) }
        #expect(noStorage.usage[.allocationBytes] == 0)
        var success = try self.context()
        let before = success.usage[.managedStorageBytes]
        _ = try SystemVerilogSyntaxParser.parse(stream, limits: normal, context: &success)
        let retained = success.usage[.managedStorageBytes] - before
        let published = UInt64(normal.nodes * MemoryLayout<SystemVerilogSyntaxNode>.stride
            + normal.children * MemoryLayout<Int>.stride + normal.symbols * MemoryLayout<Range<Int>>.stride)
        let scratch = UInt64(normal.children * MemoryLayout<SystemVerilogSyntaxParser.Link>.stride
            + normal.symbols * (2 * MemoryLayout<Int>.stride + MemoryLayout<UInt64>.stride))
        #expect(retained == published && success.usage.peakManagedStorageBytes == published + scratch)
        var failed = try self.context()
        #expect(throws: LogicKernelError.self) { try parse("module t; assign a=; endmodule", context: &failed) }
        #expect(failed.usage.peakManagedStorageBytes > failed.usage[.managedStorageBytes])
        #expect(throws: LogicKernelError.self) { try SystemVerilogSyntaxLimits(nodes: 0, children: 1, symbols: 1, nesting: 1) }
    }

    @Test func fingerprintCollisionChainsCompareBytesInsteadOfMergingNames() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        let stream = try tokens("alpha beta alpha beta", context: &context)
        var parser = SystemVerilogSyntaxParser(stream: stream,
            limits: try SystemVerilogSyntaxLimits(nodes: 100, children: 100, symbols: 10, nesting: 20))
        let alpha = try parser.identifier(context: &context)
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "beta".utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        // Force the exact internal collision-chain state without a production hash override.
        parser.symbolHeads[hash] = alpha
        let beta = try parser.identifier(context: &context)
        #expect(alpha != beta && parser.symbolNext[beta] == alpha)
        #expect(try parser.identifier(context: &context) == alpha)
        #expect(try parser.identifier(context: &context) == beta)
    }
}
