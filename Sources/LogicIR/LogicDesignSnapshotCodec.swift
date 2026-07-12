import Foundation
import XcircuitePackage

public enum LogicDesignSnapshotCodec {
    public static func encode(_ snapshot: LogicDesignSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> LogicDesignSnapshot {
        let snapshot: LogicDesignSnapshot
        do {
            snapshot = try JSONDecoder().decode(LogicDesignSnapshot.self, from: data)
        } catch {
            throw LogicDesignSnapshotCodecError.decodeFailed(error.localizedDescription)
        }
        guard snapshot.schemaVersion == LogicDesignSnapshot.currentSchemaVersion,
              snapshot.rtl.schemaVersion == RTLDesign.currentSchemaVersion else {
            throw LogicDesignSnapshotCodecError.unsupportedSchemaVersion(snapshot.schemaVersion)
        }
        if let expectedDigest = snapshot.designDigest {
            let actualDigest = try digest(snapshot)
            guard expectedDigest == actualDigest else {
                throw LogicDesignSnapshotCodecError.digestMismatch(
                    expected: expectedDigest,
                    actual: actualDigest
                )
            }
        }
        return snapshot
    }

    public static func digest(_ snapshot: LogicDesignSnapshot) throws -> String {
        let canonical = LogicDesignSnapshot(
            rtl: snapshot.rtl,
            gate: snapshot.gate,
            designDigest: nil,
            schemaVersion: snapshot.schemaVersion
        )
        return XcircuiteHasher().sha256(data: try encode(canonical))
    }

    public static func finalized(_ snapshot: LogicDesignSnapshot) throws -> LogicDesignSnapshot {
        var result = snapshot
        result.designDigest = try digest(snapshot)
        return result
    }
}
