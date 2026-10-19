import Foundation
import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore
import LogicDesignSerialization
import LogicKernelProbeSupport
@testable import SystemVerilogFrontend

@Suite(.timeLimit(.minutes(1)))
struct SourceTextTests {
    @available(macOS 15.0, *)
    private func context(storage: UInt64 = 100_000_000, work: UInt64 = 100_000_000,
                         cancelled: Bool = false) throws -> LogicKernelContext {
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(100_000_000)) })
        limits[.managedStorageBytes] = storage; limits[.workUnits] = work
        let control = LogicCancellationSource(); if cancelled { control.cancel() }
        return LogicKernelContext(limits: try LogicKernelLimits(maximums: limits), control: control)
    }
    private func document(_ text: String, context: inout LogicKernelContext) throws -> LogicSourceDocument {
        let bytes = Array(text.utf8)
        let id = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
            hexadecimalValue: LogicSourceDigest.sha256HexadecimalValue(of: Data(bytes))), byteCount: UInt64(bytes.count))
        return try LogicSourceDocument(logicalName: "source.sv", artifactID: id, bytes: bytes, context: &context)
    }
    private func origin(_ doc: LogicSourceDocument, _ range: Range<UInt64>) throws -> LogicKernelSourceRange {
        try LogicKernelSourceRange(artifactID: doc.artifactID, byteRange: range)
    }

    @Test func identityTextRetainsExactBytesAndValidatesAllRanges() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context(); let root = try document("0123456789", context: &run)
        let before = run.usage[.managedStorageBytes]
        let text = SystemVerilogSourceText(root)
        #expect(run.usage[.managedStorageBytes] == before)
        #expect(text.withBytes { $0.count == 10 && $0[5] == 53 })
        #expect(try text.origin(for: 3..<6) == origin(root, 3..<6))
        #expect(try text.origin(for: 10..<10) == origin(root, 10..<10))
        #expect(throws: LogicKernelError.self) { try text.origin(for: -1..<1) }
        #expect(throws: LogicKernelError.self) { try text.origin(for: 10..<11) }
    }

    @Test func exactAnchoredAndOrderedMultiSegmentRangesProjectToOriginalBytes() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context(); let root = try document("0123456789", context: &run)
        var bytes = Array("01ABCD89".utf8)
        let text = try SystemVerilogSourceText(root: root, bytes: bytes, segments: [
            SystemVerilogSourceSegment(textRange: 0..<2, document: root, origin: origin(root, 0..<2), isExact: true),
            SystemVerilogSourceSegment(textRange: 2..<6, document: root, origin: origin(root, 2..<8), isExact: false),
            SystemVerilogSourceSegment(textRange: 6..<8, document: root, origin: origin(root, 8..<10), isExact: true)
        ], terminalOrigin: origin(root, 10..<10), context: &run)
        bytes[0] = 90
        #expect(text.withBytes { $0[0] == 48 && $0[3] == 66 })
        #expect(try text.origin(for: 2..<4) == origin(root, 2..<8))
        #expect(try text.origin(for: 1..<7) == origin(root, 1..<9))
        #expect(try text.origin(for: 7..<8) == origin(root, 9..<10))
        #expect(try text.origin(for: 8..<8) == origin(root, 10..<10))
    }

    @Test func mixedAndDisorderedArtifactsUseTheFirstLocationWithoutInventingIdentity() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context(); let root = try document("0123456789", context: &run)
        let header = try document("XYZ", context: &run)
        let text = try SystemVerilogSourceText(root: root, bytes: Array("01XYZ89".utf8), segments: [
            SystemVerilogSourceSegment(textRange: 0..<2, document: root, origin: origin(root, 0..<2), isExact: true),
            SystemVerilogSourceSegment(textRange: 2..<5, document: header, origin: origin(header, 0..<3), isExact: true),
            SystemVerilogSourceSegment(textRange: 5..<7, document: root, origin: origin(root, 8..<10), isExact: true)
        ], terminalOrigin: origin(root, 10..<10), context: &run)
        #expect(try text.origin(for: 3..<4) == origin(header, 1..<2))
        #expect(try text.origin(for: 1..<6) == origin(root, 1..<2))
        let reversed = try SystemVerilogSourceText(root: root, bytes: Array("8901".utf8), segments: [
            SystemVerilogSourceSegment(textRange: 0..<2, document: root, origin: origin(root, 8..<10), isExact: true),
            SystemVerilogSourceSegment(textRange: 2..<4, document: root, origin: origin(root, 0..<2), isExact: true)
        ], terminalOrigin: origin(root, 2..<2), context: &run)
        #expect(try reversed.origin(for: 0..<4) == origin(root, 8..<10))
    }

    @Test func malformedMapsUTF8AndTerminalOriginsAreRejectedWithoutRetainingStorage() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var source = try context(); let root = try document("0123456789", context: &source)
        for mode in 0..<7 {
            var run = try context()
            let range = mode == 0 ? 1..<2 : mode == 1 ? 0..<0 : mode == 2 ? 0..<3 : 0..<2
            let segment = try SystemVerilogSourceSegment(textRange: range, document: root,
                origin: origin(root, mode == 3 ? 0..<1 : 0..<2), isExact: true)
            let segments = mode == 4 ? [] : mode == 5 ? [segment, segment] : [segment]
            let bytes: [UInt8] = mode == 6 ? [0xc0, 0x80] : [48, 49]
            #expect(throws: LogicKernelError.self) {
                try SystemVerilogSourceText(root: root, bytes: bytes, segments: segments,
                    terminalOrigin: origin(root, 10..<10), context: &run)
            }
            #expect(run.usage[.managedStorageBytes] == 0)
        }
        var run = try context()
        #expect(throws: LogicKernelError.self) {
            try SystemVerilogSourceText(root: root, bytes: [], segments: [],
                terminalOrigin: origin(root, 0..<1), context: &run)
        }
        let empty = try SystemVerilogSourceText(root: root, bytes: [], segments: [],
            terminalOrigin: origin(root, 5..<5), context: &run)
        #expect(empty.withBytes { $0.isEmpty })
        #expect(try empty.origin(for: 0..<0) == origin(root, 5..<5))
    }

    @Test func sourceTextResourceAndCancellationFailuresPropagate() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var source = try context(); let root = try document("01", context: &source)
        for mode in 0..<3 {
            var run = try context(storage: mode == 0 ? 1 : 100_000_000,
                work: mode == 1 ? 1 : 100_000_000, cancelled: mode == 2)
            #expect(throws: LogicKernelError.self) {
                try SystemVerilogSourceText(root: root, bytes: [48, 49], segments: [
                    SystemVerilogSourceSegment(textRange: 0..<2, document: root, origin: origin(root, 0..<2), isExact: true)
                ], terminalOrigin: origin(root, 2..<2), context: &run)
            }
            #expect(run.usage[.managedStorageBytes] == 0)
        }
    }

    @Test func equalLengthWrongBytesCannotClaimExactCorrespondence() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context(); let root = try document("01", context: &run)
        #expect(throws: LogicKernelError.self) {
            try SystemVerilogSourceText(root: root, bytes: [65, 66], segments: [
                SystemVerilogSourceSegment(textRange: 0..<2, document: root, origin: origin(root, 0..<2), isExact: true)
            ], terminalOrigin: origin(root, 2..<2), context: &run)
        }
    }

    @Test func transformedTextRetainsLocationsThroughTheActualFrontend() throws {
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        var run = try context()
        try sourceTextContractProbe(context: &run)
    }
}
