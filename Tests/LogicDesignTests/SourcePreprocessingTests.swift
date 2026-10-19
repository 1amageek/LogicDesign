import Foundation
import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicDesignSerialization
import LogicKernelProbeSupport
@testable import SystemVerilogFrontend

@Suite(.timeLimit(.minutes(1)))
struct SourcePreprocessingTests {
    @available(macOS 26.0, *)
    private func context(storage: UInt64 = 100_000_000, work: UInt64 = 100_000_000,
                         cancelled: Bool = false) throws -> LogicKernelContext {
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(100_000_000)) })
        limits[.managedStorageBytes] = storage; limits[.workUnits] = work
        let control = LogicCancellationSource(); if cancelled { control.cancel() }
        return LogicKernelContext(limits: try LogicKernelLimits(maximums: limits), control: control)
    }
    @available(macOS 26.0, *)
    private func bundle(_ texts: [(String, String)], context: inout LogicKernelContext) throws -> LogicSourceBundle {
        var documents: [LogicSourceDocument] = []
        for (name, text) in texts {
            let bytes = Array(text.utf8)
            let id = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
                hexadecimalValue: LogicSourceDigest.sha256HexadecimalValue(of: Data(bytes))), byteCount: UInt64(bytes.count))
            documents.append(try LogicSourceDocument(logicalName: name, artifactID: id, bytes: bytes, context: &context))
        }
        return try LogicSourceBundle(documents: documents, context: &context)
    }
    @available(macOS 26.0, *)
    private func preprocess(_ source: String, context: inout LogicKernelContext) throws -> String {
        let sources = try bundle([("root.sv", source)], context: &context)
        return try SystemVerilogSourcePreprocessor.preprocess(sources, roots: ["root.sv"], maximumNesting: 40, context: &context)[0]
            .withBytes { decode($0) }
    }
    private func decode(_ bytes: borrowing Span<UInt8>) -> String {
        var copy: [UInt8] = []; copy.reserveCapacity(bytes.count)
        for index in 0..<bytes.count { copy.append(bytes[index]) }
        return String(decoding: copy, as: UTF8.self)
    }
    private func compact(_ value: String) -> String { String(value.filter { !$0.isWhitespace }) }

    @Test func literalFirstSubstitutionDoesNotExpandUnusedArgumentsOrRebindIntroducedFormals() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let text = try preprocess("`define DROP(x) 7\n`define INNER(a,b) a+b\n`define OUTER(a,b) a+b\n`DROP(`UNDEFINED) `OUTER(`INNER(b,1),`INNER(42,a))", context: &run)
        #expect(compact(text) == "7b+1+42+a")
        let comma = try preprocess("`define COMMA ,\n`define COUNT(a,b) a:b\n`define WRAP(x) `COUNT(x,9)\n`WRAP(`COMMA)", context: &run)
        #expect(compact(comma) == ",:9")
    }
    @Test func callerTokensCompleteFunctionMacroAliasesAndSeparateInvocations() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let text = try preprocess("`define ID(x) x\n`define ALIAS `ID\n`define PREFIX 1+`ALIAS\n`PREFIX(2) `ALIAS(3) `ID(4)", context: &run)
        #expect(compact(text) == "1+234")
    }
    @Test func tokenAwareReplacementProtectsNumbersStringsCommentsAndEscapedIdentifiers() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let text = try preprocess("`define M(x) x+8'hx+\"x `NO\"+\\x +/*x `NO*/x // x `NO\n`M(2) tail\n", context: &run)
        #expect(text.contains("2+8'hx+\"x `NO\"+\\x +/*x `NO*/2 // x `NO\n"))
        #expect(text.contains("tail"))
        let multiline = try preprocess("`define SUM(x,y) x+\\\ny\n`SUM({1,2},(3+4))\n", context: &run)
        #expect(compact(multiline) == "{1,2}+(3+4)")
    }
    @Test func emptyBodiesEmptyArgumentsAndBalancedDelimiterArgumentsArePreserved() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        #expect(compact(try preprocess("`define E\n`define ZERO() 0\n`define PAIR(x,y) [x:y]\n`E `ZERO() `PAIR(,) `PAIR({1,2},a[2:0])", context: &run)) == "0[:][{1,2}:a[2:0]]")
    }
    @Test func orderedRootsShareConditionalAndDefinitionStateAndIncludeExactNamesOnly() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        let sources = try bundle([
            ("one.sv", "`define X 1\n`ifdef X\n`include \"inc/header\"\n"),
            ("inc/header", "`define Y 2\nheader\n"),
            ("two.sv", "`X `Y\n`elsif MISSING\n`include \"absent\"\n`UNDEFINED\n`else\ninvalid\n`endif\n`undef X\n`ifndef X\nyes\n`endif\n`undefineall\n`ifdef Y\nbad\n`else\nend\n`endif")], context: &run)
        let outputs = try SystemVerilogSourcePreprocessor.preprocess(sources, roots: ["one.sv", "two.sv"], maximumNesting: 40, context: &run)
        #expect(compact(outputs[0].withBytes { decode($0) }) == "header")
        #expect(compact(outputs[1].withBytes { decode($0) }) == "12yesend")
    }
    @Test func malformedUnsupportedAndRecursiveInputsReturnLocatedFailures() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        let cases = [
            ("`MISSING", "SV_PP_UNDEFINED_MACRO"),
            ("`define R `R\n`R", "SV_PP_MACRO_CYCLE"),
            ("`define A `B\n`define B `A\n`A", "SV_PP_MACRO_CYCLE"),
            ("`define M(x) x\n`M([1})", "SV_PP_ARGUMENT_DELIMITER"),
            ("`define M(x,y) x\n`M(1)", "SV_PP_ARGUMENT_COUNT"),
            ("`define M(x) x\n`M", "SV_PP_ARGUMENT_LIST"),
            ("`define M(x=1) x\n", "SV_PP_FORMAL_LIST"),
            ("`define M(x,x) x\n", "SV_PP_DUPLICATE_FORMAL"),
            ("`define P a``b\n`P", "SV_PP_MACRO_OPERATOR_UNSUPPORTED"),
            ("`define D `ifdef X\n`D", "SV_PP_EXPANDED_DIRECTIVE"),
            ("`else\n", "SV_PP_CONDITIONAL_ORDER"),
            ("`ifdef X\n`else\n`else\n", "SV_PP_CONDITIONAL_ORDER"),
            ("`ifdef X\n", "SV_PP_UNCLOSED_CONDITIONAL"),
            ("`include \"./header\"", "SV_PP_INCLUDE_MISSING"),
            ("`include <header>", "SV_PP_INCLUDE_NAME")]
        for (source, expected) in cases {
            var run = try context()
            let sources = try bundle([("root.sv", source)], context: &run)
            do {
                _ = try SystemVerilogSourcePreprocessor.preprocess(sources, roots: ["root.sv"], maximumNesting: 40, context: &run)
                Issue.record("Invalid preprocessing input was accepted: \(expected)")
            } catch {
                guard case .sourceFailure(let code, let origin, _) = error else { Issue.record("Unexpected error: \(error)"); continue }
                #expect(code.rawValue == expected)
                #expect(origin.artifactID == (try sources.document(at: 0)).artifactID)
            }
        }
    }
    @Test func cyclesNestingMissingRootsCancellationAndResourceLimitsCannotPublishSuccess() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var setup = try context()
        let sources = try bundle([("root.sv", "`include \"header\""), ("header", "`include \"root.sv\"")], context: &setup)
        for mode in 0..<6 {
            var run = try context(storage: mode == 3 ? 1 : 100_000_000, work: mode == 4 ? 1 : 100_000_000, cancelled: mode == 5)
            #expect(throws: LogicKernelError.self) {
                try SystemVerilogSourcePreprocessor.preprocess(sources, roots: mode == 1 ? ["missing"] : ["root.sv"],
                    maximumNesting: mode == 2 ? 1 : 40, context: &run)
            }
            #expect(run.usage[.managedStorageBytes] == 0)
        }
    }
    @Test func expandedAndIncludedOriginsSurviveTheActualFrontendAndBorrowedSegmentCopy() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        try sourcePreprocessingContractProbe(context: &run)
        let sources = try bundle([("root.sv", "A\n`include \"header\"\nZ"), ("header", "0123456789")], context: &run)
        let text = try SystemVerilogSourcePreprocessor.preprocess(sources, roots: ["root.sv"], maximumNesting: 40, context: &run)[0]
        var copy = try SystemVerilogTextBuffer(context: &run)
        try copy.append(text, range: 3..<8, context: &run)
        let cloned = try copy.finish(root: text.root, terminalOrigin: text.origin(for: 8..<8), context: &run)
        #expect(cloned.withBytes { decode($0) } == "12345")
        #expect(try cloned.origin(for: 1..<4) == LogicKernelSourceRange(artifactID: sources.document(at: 1).artifactID, byteRange: 2..<5))
    }
}
