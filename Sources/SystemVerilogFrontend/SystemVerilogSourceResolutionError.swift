import Foundation
import LogicIR

public enum SystemVerilogSourceResolutionError: Error, Sendable, Hashable, Codable, LocalizedError {
    case malformedInclude(sourcePath: String, location: LogicSourceSpan)
    case missingInclude(path: String, includingPath: String, location: LogicSourceSpan)
    case cyclicInclude(path: String, chain: [String], location: LogicSourceSpan)

    public var errorDescription: String? {
        switch self {
        case .malformedInclude(let sourcePath, _):
            return "The include directive in \(sourcePath) does not contain a quoted path."
        case .missingInclude(let path, let includingPath, _):
            return "The SystemVerilog include \(path) referenced by \(includingPath) could not be loaded."
        case .cyclicInclude(let path, let chain, _):
            return "The SystemVerilog include graph contains a cycle at \(path): \(chain.joined(separator: " -> "))."
        }
    }

    public var location: LogicSourceSpan {
        switch self {
        case .malformedInclude(_, let location),
             .missingInclude(_, _, let location),
             .cyclicInclude(_, _, let location):
            return location
        }
    }

    public var diagnosticCode: String {
        switch self {
        case .malformedInclude: return "SV_INCLUDE_MALFORMED"
        case .missingInclude: return "SV_INCLUDE_MISSING"
        case .cyclicInclude: return "SV_INCLUDE_CYCLE"
        }
    }
}
