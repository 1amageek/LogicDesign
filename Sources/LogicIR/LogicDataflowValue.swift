public indirect enum LogicDataflowValue: Sendable, Hashable, Codable {
    case bits(LogicBitVector)
    case tuple([LogicDataflowValue])
    case array([LogicDataflowValue])
    case token

    public func matches(_ type: LogicDataflowType) -> Bool {
        switch (self, type) {
        case (.bits(let value), .bits(let width)):
            return value.width == width
        case (.tuple(let values), .tuple(let types)):
            return values.count == types.count
                && zip(values, types).allSatisfy { $0.matches($1) }
        case (.array(let values), .array(let element, let count)):
            return values.count == count && values.allSatisfy { $0.matches(element) }
        case (.token, .token):
            return true
        default:
            return false
        }
    }
}
