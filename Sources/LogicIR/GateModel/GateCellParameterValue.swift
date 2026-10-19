public enum GateCellParameterValue: Sendable, Hashable {
    case boolean(Bool)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case string(String)
    case integerList([Int64])
    case bitVector(String)
}
