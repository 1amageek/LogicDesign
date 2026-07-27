public indirect enum LogicDataflowType: Sendable, Hashable, Codable {
    case bits(width: Int)
    case tuple([LogicDataflowType])
    case array(element: LogicDataflowType, count: Int)
    case token

    public var isValid: Bool {
        switch self {
        case .bits(let width):
            return width > 0
        case .tuple(let elements):
            return elements.allSatisfy(\.isValid)
        case .array(let element, let count):
            return count > 0 && element.isValid
        case .token:
            return true
        }
    }
}
