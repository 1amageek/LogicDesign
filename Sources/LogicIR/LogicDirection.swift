import Foundation

public enum LogicDirection: String, Sendable, Hashable, Codable {
    case input
    case output
    case inOut
    case internalSignal
}
