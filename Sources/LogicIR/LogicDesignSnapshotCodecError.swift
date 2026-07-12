import Foundation

public enum LogicDesignSnapshotCodecError: Error, Sendable, Hashable, Codable, LocalizedError {
    case decodeFailed(String)
    case unsupportedSchemaVersion(Int)
    case digestMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .decodeFailed(let message):
            return "Logic design snapshot decoding failed: \(message)."
        case .unsupportedSchemaVersion(let version):
            return "Logic design snapshot schema version \(version) is not supported."
        case .digestMismatch(let expected, let actual):
            return "Logic design snapshot digest mismatch: expected \(expected), got \(actual)."
        }
    }
}
