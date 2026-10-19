import Foundation
import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicDesignSerialization
import SystemVerilogFrontend

@Suite(.timeLimit(.minutes(1)))
struct SynthesisIntegerLiteralTests {
    private struct Control: LogicRunControlling { func checkpoint() throws(LogicKernelError) {} }
    private struct Cancelled: LogicRunControlling { func checkpoint() throws(LogicKernelError) { throw .cancelled } }
    private func context(width: UInt64 = 1_000_000, storage: UInt64 = 1_000_000) throws -> LogicKernelContext {
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) })
        limits[.bitWidth] = width; limits[.managedStorageBytes] = storage
        return LogicKernelContext(limits: try LogicKernelLimits(maximums: limits), control: Control())
    }
    private func source(_ text: String, context: inout LogicKernelContext) throws -> LogicSourceDocument {
        let bytes = Array(text.utf8)
        let id = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
            hexadecimalValue: LogicSourceDigest.sha256HexadecimalValue(of: Data(bytes))), byteCount: UInt64(bytes.count))
        return try LogicSourceDocument(logicalName: "literal.sv", artifactID: id, bytes: bytes, context: &context)
    }
    @available(macOS 26.0, *)
    private func decode(_ text: String) throws -> SystemVerilogSynthesisLiteral {
        var context = try context(); let document = try source(text, context: &context)
        let decoder: any SystemVerilogSynthesisLiteralDecoding = SystemVerilogSynthesisIntegerDecoder()
        return try decoder.decode(0..<document.byteCount, in: document, context: &context)
    }

    @Test func arbitraryWidthDecimalAndBasedLiteralsKeepEveryBit() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for (text, width, signed, unsized): (String, Int, Bool, Bool) in [
            ("340282366920938463463374607431768211456", 130, true, true),
            ("129'd340282366920938463463374607431768211456", 129, false, false),
            ("129'sh1_00000000000000000000000000000000", 129, true, false),
            ("'h1_00000000000000000000000000000000", 129, false, true)
        ] {
            guard case .integer(let value, let actualSigned, let actualUnsized) = try decode(text) else { Issue.record("Expected vector"); continue }
            #expect(value.width.value == width && actualSigned == signed && actualUnsized == unsized)
            #expect(try value.bit(at: 128) == .one)
            #expect(value.withPlanes { values, unknowns in values[0] == 0 && values[1] == 0 && values[2] == 1
                && unknowns[0] == 0 && unknowns[1] == 0 && unknowns[2] == 0 })
        }
    }

    @Test func signedMarkerIsIndependentOfBaseCaseAndDigitPadding() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for (text, signed, width, expected): (String, Bool, Int, UInt64) in [
            ("8'Hff", false, 8, 255), ("8'shff", true, 8, 255),
            ("16'SHf", true, 16, 15), ("8 'D 259", false, 8, 3),
            ("'sh80000000", true, 32, 2_147_483_648),
            ("2147483648", true, 33, 2_147_483_648),
            ("'d2147483648", false, 32, 2_147_483_648),
            ("0", true, 32, 0), ("8'o377", false, 8, 255), ("8'b1_01", false, 8, 5)
        ] {
            guard case .integer(let value, let actualSigned, _) = try decode(text) else { Issue.record("Expected integer"); continue }
            #expect(value.width.value == width && signed == actualSigned)
            #expect(value.withPlanes { $0[0] == expected && $1[0] == 0 })
        }
        #expect(try decode("'0") == .fill(false))
        #expect(try decode(" '1 ") == .fill(true))
    }

    @Test func sizedValuesMatchIndependentSmallIntegerModulo() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for width in 1...16 {
            for integer in stride(from: 0, through: 1023, by: 17) {
                for base in [2, 8, 10, 16] {
                    let token = base == 2 ? "b" : base == 8 ? "o" : base == 10 ? "d" : "h"
                    guard case .integer(let value, _, _) = try decode("\(width)'\(token)\(String(integer, radix: base))") else {
                        Issue.record("Expected integer"); continue
                    }
                    let expected = UInt64(integer) & ((UInt64(1) << width) - 1)
                    #expect(value.withPlanes { $0[0] == expected && $1[0] == 0 })
                }
            }
        }
    }

    @Test func malformedOrUnknownLiteralsFailAtTheExactSource() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        for text in ["8'b2", "4'o8", "4'hg", "0'h1", "8'h", "8'", "8's h1", "8'h_1", "8'h1 2",
                     "8'hx", "8'dz", "8'b?", "'x", "'z", "'?", "-1", "_1", "999999999999999999999999999999999'h1"] {
            var context = try context(); let document = try source(text, context: &context)
            do {
                _ = try SystemVerilogSynthesisIntegerDecoder().decode(0..<document.byteCount, in: document, context: &context)
                Issue.record("Invalid or unsupported integer literal was accepted")
            } catch {
                guard case .sourceFailure(_, let origin, _) = error else { Issue.record("Lost source location"); continue }
                #expect(origin.artifactID == document.artifactID && origin.byteRange.upperBound <= document.artifactID.byteCount)
            }
        }
    }

    @Test func widthAndOverlappingStorageAreBoundedBeforePublication() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var context = try context(); let document = try source("129'h1", context: &context)
        var width = try self.context(width: 128)
        #expect(throws: LogicKernelError.resourceLimit(resource: .bitWidth, limit: 128, requested: 129)) {
            try SystemVerilogSynthesisIntegerDecoder().decode(0..<document.byteCount, in: document, context: &width)
        }
        var storage = try self.context(storage: 60)
        #expect(throws: LogicKernelError.resourceLimit(resource: .managedStorageBytes, limit: 60, requested: 72)) {
            try SystemVerilogSynthesisIntegerDecoder().decode(0..<document.byteCount, in: document, context: &storage)
        }
        #expect(storage.usage[.managedStorageBytes] == 0)
        #expect(throws: LogicKernelError.self) {
            try SystemVerilogSynthesisIntegerDecoder().decode(-1..<0, in: document, context: &context)
        }
    }

    @Test func contextualFillStillChecksRunControl() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var preparation = try context(); let document = try source("'1", context: &preparation)
        var cancelled = LogicKernelContext(limits: preparation.limits, control: Cancelled())
        #expect(throws: LogicKernelError.cancelled) {
            try SystemVerilogSynthesisIntegerDecoder().decode(0..<2, in: document, context: &cancelled)
        }
    }
}
