public enum LogicDataflowAttributeValue: Sendable, Hashable, Codable {
    case integer(Int64)
    case unsignedInteger(UInt64)
    case boolean(Bool)
    case identifier(String)
    case identifiers([String])
    case text(String)
    case literal(LogicDataflowValue)
}
