import Foundation

public enum LogicStorageKind: String, Sendable, Hashable, Codable {
    case combinational
    case register
    case memory
    case net
}
