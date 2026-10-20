import Foundation
import CircuiteFoundation
import LogicKernelCore

/// Schema-local logical sizes. These are payloads, not allocator/RSS estimates.
internal struct LogicGraphJSONSize {
    private(set) var value = 0
    mutating func add(_ amount: Int) throws { value = try LogicGraphJSONPreflight.add(value, amount) }
    mutating func array<Element>(_ count: Int, of: Element.Type) throws {
        try add(LogicGraphJSONPreflight.multiply(count, MemoryLayout<Element>.stride))
    }
    static func integer(_ value: Int) -> Int {
        var magnitude = value.magnitude; var count = value < 0 ? 1 : 0
        repeat { count += 1; magnitude /= 10 } while magnitude > 0
        return count
    }
    static func unsigned(_ value: UInt64) -> Int {
        var magnitude = value; var count = 0
        repeat { count += 1; magnitude /= 10 } while magnitude > 0
        return count
    }
    static func boolean(_ value: Bool) -> Int { value ? 4 : 5 }
    static func quoted(_ value: StaticString) -> Int { value.utf8CodeUnitCount + 2 }
    static func arrayHeader(_ count: Int) throws -> Int { try LogicGraphJSONPreflight.add(2, max(count - 1, 0)) }
    static func objectHeader(_ count: Int) -> Int { 2 + max(count - 1, 0) }
    mutating func field(_ name: StaticString, _ payload: Int) throws {
        try add(name.utf8CodeUnitCount + 3)
        try add(payload)
    }
    static func string(_ value: String, context: inout LogicKernelContext) throws -> Int {
        var size = Self(); try size.add(2)
        for scalar in value.unicodeScalars {
            try context.charge(.workUnits)
            switch scalar.value {
            case 34, 92, 8, 9, 10, 12, 13: try size.add(2)
            case 0..<32: try size.add(6)
            case 32..<127: try size.add(1)
            case 127...0xffff: try size.add(6)
            default: try size.add(12)
            }
        }
        return size.value
    }
    static func artifact(_ value: ArtifactID) throws -> Int {
        // ArtifactID.canonicalBytes: domain, NUL, version, two UInt16 lengths,
        // exact algorithm bytes, digest bytes and UInt64 content length.
        var bytes = Self(); try bytes.add("CircuiteArtifactContent".utf8.count + 1 + 2 + 2 + 2 + 8)
        try bytes.add(value.digest.algorithm.rawValue.utf8.count)
        try bytes.add(value.digest.hexadecimalValue.utf8.count / 2)
        return try LogicGraphJSONPreflight.add(2, LogicGraphJSONPreflight.multiply(bytes.value, 2))
    }
    static func decodedStrings(_ counts: LogicGraphJSONPreflight.Counts) throws -> Int {
        var size = Self()
        try size.array(counts.strings, of: String.self)
        try size.add(counts.stringBytes)
        // FixedWidthHexadecimal.decode64 materializes exactly the field's UTF-8 array.
        try size.array(counts.identifiers, of: [UInt8].self)
        try size.add(counts.identifierBytes)
        // CF5f ArtifactID decoding: H encoded bytes, H/2 decoded bytes;
        // A+D <= H/2 by cursor bounds. All remaining transient byte payloads
        // are bounded by 6A+5D (including invalid-UTF8 replacement at 3A).
        // Two domain arrays (22 each) and the 16-byte hex digit table coexist.
        let decoded = counts.artifactHexBytes / 2
        try size.add(counts.artifactHexBytes)
        try size.add(LogicGraphJSONPreflight.multiply(decoded, 7))
        try size.add(LogicGraphJSONPreflight.multiply(counts.artifacts, 60))
        try size.array(try LogicGraphJSONPreflight.multiply(counts.artifacts, 9), of: [UInt8].self)
        try size.array(try LogicGraphJSONPreflight.multiply(counts.artifacts, 3), of: String.self)
        return size.value
    }
    static func decodedArtifactBacking(_ counts: LogicGraphJSONPreflight.Counts) throws -> Int {
        // Returned algorithm and lowercase digest strings: A+2D <= 2*(H/2).
        var size = Self()
        try size.add(counts.artifactHexBytes)
        try size.array(try LogicGraphJSONPreflight.multiply(counts.artifacts, 2), of: String.self)
        return size.value
    }
    static func encodedIdentifierScratch(_ count: Int) throws -> Int {
        // CF5f uses two 16-byte arrays and one 16-byte String per identifier.
        var size = Self()
        try size.add(LogicGraphJSONPreflight.multiply(count, 48))
        try size.array(try LogicGraphJSONPreflight.multiply(count, 2), of: [UInt8].self)
        try size.array(count, of: String.self)
        return size.value
    }
    static func encodedArtifactScratch(_ artifact: ArtifactID) throws -> Int {
        let hex = try Self.artifact(artifact) - 2
        let bytes = hex / 2
        var size = Self()
        // canonicalBytes old/new growth, encoded hex array and resulting String.
        try size.add(LogicGraphJSONPreflight.multiply(bytes, 6))
        try size.add(artifact.digest.algorithm.rawValue.utf8.count)
        try size.add(LogicGraphJSONPreflight.multiply(artifact.digest.hexadecimalValue.utf8.count / 2, 3))
        // Big-endian scalar arrays (2+2+2+8) and the 16-byte digit array.
        try size.add(30)
        try size.array(12, of: [UInt8].self)
        try size.array(3, of: String.self)
        return size.value
    }
    static func reserve(_ bytes: Int, context: inout LogicKernelContext) throws -> LogicStorageReservation {
        guard bytes >= 0 else { throw LogicKernelError.invalidInput("Negative controlled codec storage") }
        return try context.reserveStorage(byteCount: UInt64(bytes))
    }
}
