import Foundation

public enum RTLProcessKind: String, Sendable, Hashable, Codable {
    case combinational
    case sequential
    case latch
    case generic
}
