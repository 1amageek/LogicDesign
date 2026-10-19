public enum LogicBit: UInt8, Sendable, Hashable {
    case zero = 0
    case one = 1
    case unknown = 2
    case highImpedance = 3

    public var isKnown: Bool { self == .zero || self == .one }

    public var inverted: Self {
        switch self {
        case .zero: .one
        case .one: .zero
        case .unknown, .highImpedance: .unknown
        }
    }

    public func and(_ other: Self) -> Self {
        if self == .zero || other == .zero { return .zero }
        if self == .one && other == .one { return .one }
        return .unknown
    }

    public func or(_ other: Self) -> Self {
        if self == .one || other == .one { return .one }
        if self == .zero && other == .zero { return .zero }
        return .unknown
    }

    public func xor(_ other: Self) -> Self {
        guard isKnown && other.isKnown else { return .unknown }
        return self == other ? .zero : .one
    }

    public func selecting(ifTrue: Self, ifFalse: Self) -> Self {
        switch self {
        case .zero: ifFalse
        case .one: ifTrue
        case .unknown, .highImpedance: ifTrue.isKnown && ifTrue == ifFalse ? ifTrue : .unknown
        }
    }
}
