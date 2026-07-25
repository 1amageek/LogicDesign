import Foundation

public enum GateCellParameterValue: Sendable, Hashable, Codable {
    case boolean(Bool)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case string(String)
    case integerList([Int64])
    case bitVector(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case boolean
        case integer
        case unsignedInteger
        case string
        case integerList
        case bitVector
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .boolean:
            self = .boolean(try container.decode(Bool.self, forKey: .value))
        case .integer:
            self = .integer(try container.decode(Int64.self, forKey: .value))
        case .unsignedInteger:
            self = .unsignedInteger(try container.decode(UInt64.self, forKey: .value))
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .integerList:
            self = .integerList(try container.decode([Int64].self, forKey: .value))
        case .bitVector:
            self = .bitVector(try container.decode(String.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .boolean(let value):
            try container.encode(Kind.boolean, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .integer(let value):
            try container.encode(Kind.integer, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .unsignedInteger(let value):
            try container.encode(Kind.unsignedInteger, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .string(let value):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .integerList(let value):
            try container.encode(Kind.integerList, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .bitVector(let value):
            try container.encode(Kind.bitVector, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }
}
