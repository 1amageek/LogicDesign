import Foundation
import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicDesignSerialization
import SystemVerilogFrontend

@Suite(.timeLimit(.minutes(1)))
struct PortableSourceTests {
    private struct Control: LogicRunControlling { func checkpoint() throws(LogicKernelError) {} }
    private struct Cancelled: LogicRunControlling { func checkpoint() throws(LogicKernelError) { throw .cancelled } }
    private func context(control: any LogicRunControlling = Control(), storage: UInt64 = 1_000_000,
                         work: UInt64 = 1_000_000) throws -> LogicKernelContext {
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) })
        limits[.managedStorageBytes] = storage; limits[.workUnits] = work
        return LogicKernelContext(limits: try LogicKernelLimits(maximums: limits), control: control)
    }
    private func artifact(_ bytes: [UInt8]) throws -> ArtifactID {
        try ArtifactID(digest: ContentDigest(algorithm: .sha256,
            hexadecimalValue: LogicSourceDigest.sha256HexadecimalValue(of: Data(bytes))), byteCount: UInt64(bytes.count))
    }
    private func source(_ text: String, name: String = "input.sv", context: inout LogicKernelContext) throws -> LogicSourceDocument {
        let bytes = Array(text.utf8)
        return try LogicSourceDocument(logicalName: name, artifactID: artifact(bytes), bytes: bytes, context: &context)
    }

    @Test func exactBytesRemainImmutableAndNamesAreUnique() throws {
        var context = try context()
        var bytes: [UInt8] = [65, 0xc2, 0xa2, 0xe2, 0x82, 0xac, 0xf0, 0x90, 0x80, 0x80]
        let document = try LogicSourceDocument(logicalName: "units/α.sv", artifactID: artifact(bytes), bytes: bytes, context: &context)
        bytes[0] = 90
        let bundle = try LogicSourceBundle(documents: [document], context: &context)
        #expect(try bundle.document(at: 0).artifactID == document.artifactID)
        #expect(throws: LogicKernelError.self) { try bundle.document(at: 1) }
        #expect(throws: LogicKernelError.self) { try LogicSourceBundle(documents: [document, document], context: &context) }
        #expect(throws: LogicKernelError.self) { try LogicSourceBundle(documents: [], context: &context) }
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        #expect(document.withBytes { $0[0] == 65 && $0.count == 10 })
        #expect(bundle.withDocuments { $0.count == 1 && $0[0].logicalName == "units/α.sv" })
        let empty = try source("", context: &context)
        #expect(empty.withBytes { $0.isEmpty })
    }

    @Test func malformedUTF8AndMismatchedIdentityAreRejected() throws {
        for bytes: [UInt8] in [[0x80], [0xc0, 0x80], [0xc2], [0xe0, 0x9f, 0x80],
                               [0xed, 0xa0, 0x80], [0xf0, 0x8f, 0x80, 0x80],
                               [0xf4, 0x90, 0x80, 0x80], [0xf5, 0x80, 0x80, 0x80], [0xc2, 65]] {
            var context = try context()
            let id = try artifact(bytes)
            #expect(throws: LogicKernelError.self) {
                try LogicSourceDocument(logicalName: "bad.sv", artifactID: id, bytes: bytes, context: &context)
            }
        }
        var context = try context()
        #expect(throws: LogicKernelError.self) {
            try LogicSourceDocument(logicalName: "bad.sv", artifactID: artifact([]), bytes: [65], context: &context)
        }
        #expect(throws: LogicKernelError.self) {
            try LogicSourceDocument(logicalName: "", artifactID: artifact([]), bytes: [], context: &context)
        }
    }

    @Test func tokenRangesUseUTF8OffsetsAndLongestOperators() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        let document = try source("/*日本*/ module \\日本語 129'sh1 <<< 2; a >>>= 1; \"x\\\"y\" '1", context: &context)
        let lexer: any SystemVerilogTokenizing = SystemVerilogByteLexer()
        let stream = try lexer.tokenize(document, maximumTokens: 30, context: &context)
        let spellings: [String] = stream.withTokens { tokens in
            document.withBytes { bytes in
                var values: [String] = []
                for index in tokens.indices {
                    var spelling: [UInt8] = []
                    for offset in tokens[index].byteRange { spelling.append(bytes[offset]) }
                    values.append(String(decoding: spelling, as: UTF8.self))
                }
                return values
            }
        }
        #expect(spellings == ["module", "\\日本語", "129'sh1", "<<<", "2", ";", "a", ">>>=", "1", ";", "\"x\\\"y\"", "'1", ""])
        #expect(stream.withTokens { $0[0].byteRange.lowerBound == 11 && $0[1].kind == .escapedIdentifier
            && $0[$0.count - 1].byteRange == document.byteCount..<document.byteCount })
    }

    @Test func lexicalFailuresCarryExactArtifactAndRange() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for (text, code, range): (String, String, Range<UInt64>) in [
            ("/*日本", "SV_LEX_UNTERMINATED_COMMENT", 0..<8),
            ("\"a\n", "SV_LEX_UNTERMINATED_STRING", 0..<2),
            ("\"a\\", "SV_LEX_UNTERMINATED_STRING", 0..<3),
            ("\\ ", "SV_LEX_EMPTY_IDENTIFIER", 0..<1),
            ("//日本\nα", "SV_LEX_INVALID_CHARACTER", 9..<10)
        ] {
            var context = try context()
            let document = try source(text, context: &context)
            do {
                _ = try SystemVerilogByteLexer().tokenize(document, maximumTokens: 20, context: &context)
                Issue.record("Malformed lexical input was accepted")
            } catch {
                guard case .sourceFailure(let actualCode, let source, _) = error else { Issue.record("Lost source error"); continue }
                #expect(actualCode.rawValue == code)
                #expect(source.artifactID == document.artifactID && source.byteRange == range)
            }
        }
    }

    @Test func capacityWorkAndCancellationFailWithoutSuccessfulStream() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context()
        let document = try source("a", context: &context)
        #expect(throws: LogicKernelError.self) { try SystemVerilogByteLexer().tokenize(document, maximumTokens: 1, context: &context) }
        var cancelled = try self.context(control: Cancelled())
        #expect(throws: LogicKernelError.cancelled) { try SystemVerilogByteLexer().tokenize(document, maximumTokens: 2, context: &cancelled) }
        var storage = try self.context(storage: 1)
        #expect(throws: LogicKernelError.self) { try SystemVerilogByteLexer().tokenize(document, maximumTokens: 2, context: &storage) }
        var work = try self.context(work: 1)
        let expensive = try source("/* long comment */", context: &context)
        #expect(throws: LogicKernelError.self) { try SystemVerilogByteLexer().tokenize(expensive, maximumTokens: 1, context: &work) }
        let empty = try source("", context: &context)
        #expect(try SystemVerilogByteLexer().tokenize(empty, maximumTokens: 1, context: &context).count == 1)
    }
}
