public struct LogicDataflowOperationKind: Sendable, Hashable, Codable, RawRepresentable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty,
              rawValue.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            return nil
        }
        self.rawValue = rawValue
    }

    private init(uncheckedRawValue: String) {
        self.rawValue = uncheckedRawValue
    }

    public static let unsupported = Self(uncheckedRawValue: "unsupported")
    public static let literal = Self(uncheckedRawValue: "literal")
    public static let identity = Self(uncheckedRawValue: "identity")
    public static let add = Self(uncheckedRawValue: "add")
    public static let subtract = Self(uncheckedRawValue: "subtract")
    public static let signedMultiply = Self(uncheckedRawValue: "signedMultiply")
    public static let unsignedMultiply = Self(uncheckedRawValue: "unsignedMultiply")
    public static let signedDivide = Self(uncheckedRawValue: "signedDivide")
    public static let unsignedDivide = Self(uncheckedRawValue: "unsignedDivide")
    public static let signedModulo = Self(uncheckedRawValue: "signedModulo")
    public static let unsignedModulo = Self(uncheckedRawValue: "unsignedModulo")
    public static let negate = Self(uncheckedRawValue: "negate")
    public static let bitwiseNot = Self(uncheckedRawValue: "bitwiseNot")
    public static let bitwiseAnd = Self(uncheckedRawValue: "bitwiseAnd")
    public static let bitwiseNand = Self(uncheckedRawValue: "bitwiseNand")
    public static let bitwiseOr = Self(uncheckedRawValue: "bitwiseOr")
    public static let bitwiseNor = Self(uncheckedRawValue: "bitwiseNor")
    public static let bitwiseXor = Self(uncheckedRawValue: "bitwiseXor")
    public static let reduceAnd = Self(uncheckedRawValue: "reduceAnd")
    public static let reduceOr = Self(uncheckedRawValue: "reduceOr")
    public static let reduceXor = Self(uncheckedRawValue: "reduceXor")
    public static let equal = Self(uncheckedRawValue: "equal")
    public static let notEqual = Self(uncheckedRawValue: "notEqual")
    public static let signedGreaterThanOrEqual = Self(uncheckedRawValue: "signedGreaterThanOrEqual")
    public static let signedGreaterThan = Self(uncheckedRawValue: "signedGreaterThan")
    public static let signedLessThanOrEqual = Self(uncheckedRawValue: "signedLessThanOrEqual")
    public static let signedLessThan = Self(uncheckedRawValue: "signedLessThan")
    public static let unsignedGreaterThanOrEqual = Self(uncheckedRawValue: "unsignedGreaterThanOrEqual")
    public static let unsignedGreaterThan = Self(uncheckedRawValue: "unsignedGreaterThan")
    public static let unsignedLessThanOrEqual = Self(uncheckedRawValue: "unsignedLessThanOrEqual")
    public static let unsignedLessThan = Self(uncheckedRawValue: "unsignedLessThan")
    public static let shiftLeftLogical = Self(uncheckedRawValue: "shiftLeftLogical")
    public static let shiftRightArithmetic = Self(uncheckedRawValue: "shiftRightArithmetic")
    public static let shiftRightLogical = Self(uncheckedRawValue: "shiftRightLogical")
    public static let concatenate = Self(uncheckedRawValue: "concatenate")
    public static let reverseBits = Self(uncheckedRawValue: "reverseBits")
    public static let tuple = Self(uncheckedRawValue: "tuple")
    public static let tupleIndex = Self(uncheckedRawValue: "tupleElement")
    public static let afterAll = Self(uncheckedRawValue: "sequenceTokens")
    public static let stateRead = Self(uncheckedRawValue: "stateRead")
    public static let nextValue = Self(uncheckedRawValue: "stateNext")
    public static let send = Self(uncheckedRawValue: "channelSend")
    public static let receive = Self(uncheckedRawValue: "channelReceive")

    public static let supportedCanonicalKinds: Set<Self> = [
        .literal,
        .identity,
        .add,
        .subtract,
        .signedMultiply,
        .unsignedMultiply,
        .signedDivide,
        .unsignedDivide,
        .signedModulo,
        .unsignedModulo,
        .negate,
        .bitwiseNot,
        .bitwiseAnd,
        .bitwiseNand,
        .bitwiseOr,
        .bitwiseNor,
        .bitwiseXor,
        .reduceAnd,
        .reduceOr,
        .reduceXor,
        .equal,
        .notEqual,
        .signedGreaterThanOrEqual,
        .signedGreaterThan,
        .signedLessThanOrEqual,
        .signedLessThan,
        .unsignedGreaterThanOrEqual,
        .unsignedGreaterThan,
        .unsignedLessThanOrEqual,
        .unsignedLessThan,
        .shiftLeftLogical,
        .shiftRightArithmetic,
        .shiftRightLogical,
        .concatenate,
        .reverseBits,
        .tuple,
        .tupleIndex,
        .afterAll,
        .stateRead,
        .nextValue,
        .send,
        .receive,
    ]
}
