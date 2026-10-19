import Foundation

public enum SystemVerilogTokenKind: String, Sendable, Hashable, Codable {
    case identifier
    case number
    case string
    case keyword
    case symbol
    case `operator`
    case endOfFile
}
