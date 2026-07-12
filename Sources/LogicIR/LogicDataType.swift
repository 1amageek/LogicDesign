import Foundation

public enum LogicDataType: String, Sendable, Hashable, Codable {
    case wire
    case logic
    case reg
    case integer
    case real
    case time
    case unknown
}
