import Foundation

public enum LogicDesignOracleCorrelationError: Error, LocalizedError, Sendable {
    case unsupportedManifestSchema(Int)
    case duplicateCaseID(String)
    case caseNotFound(String)
    case invalidCase(String)
    case sourceDigestMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedManifestSchema(let version):
            return "Unsupported LogicDesign oracle manifest schema version: \(version)."
        case .duplicateCaseID(let id):
            return "LogicDesign oracle manifest contains duplicate case ID: \(id)."
        case .caseNotFound(let id):
            return "LogicDesign oracle case was not found: \(id)."
        case .invalidCase(let reason):
            return "Invalid LogicDesign oracle case: \(reason)."
        case .sourceDigestMismatch(let expected, let actual):
            return "LogicDesign oracle source digest mismatch: expected \(expected), actual \(actual)."
        }
    }
}
