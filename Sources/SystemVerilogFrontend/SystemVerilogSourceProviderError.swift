import Foundation

public enum SystemVerilogSourceProviderError: Error, Sendable, Hashable, Codable, LocalizedError {
    case invalidPath(String)
    case readFailed(path: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path): return "Source path is outside the configured project root: \(path)"
        case .readFailed(let path, let message): return "Could not read SystemVerilog source \(path): \(message)"
        }
    }
}
