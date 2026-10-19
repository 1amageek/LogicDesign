import LogicIR
import Foundation

public enum LogicDesignSnapshotCodecError: Error, Sendable, Hashable, Codable, LocalizedError {
    case validationFailed([LogicDiagnostic])
    case decodeFailed(String)
    case unsupportedSchemaVersion(Int)
    case digestMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .validationFailed(let diagnostics):
            return "Logic design validation failed: " + diagnostics.map(\.code).joined(separator: ", ")
        case .decodeFailed(let message):
            return "Logic design snapshot decoding failed: \(message)."
        case .unsupportedSchemaVersion(let version):
            return "Logic design snapshot schema version \(version) is not supported."
        case .digestMismatch(let expected, let actual):
            return "Logic design snapshot digest mismatch: expected \(expected), got \(actual)."
        }
    }
}
