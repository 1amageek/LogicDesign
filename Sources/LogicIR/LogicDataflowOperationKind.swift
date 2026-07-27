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

    public static let literal = Self(uncheckedRawValue: "literal")
    public static let identity = Self(uncheckedRawValue: "identity")
    public static let add = Self(uncheckedRawValue: "add")
    public static let subtract = Self(uncheckedRawValue: "sub")
    public static let bitwiseAnd = Self(uncheckedRawValue: "and")
    public static let bitwiseOr = Self(uncheckedRawValue: "or")
    public static let bitwiseXor = Self(uncheckedRawValue: "xor")
    public static let concatenate = Self(uncheckedRawValue: "concat")
    public static let tuple = Self(uncheckedRawValue: "tuple")
    public static let tupleIndex = Self(uncheckedRawValue: "tuple_index")
    public static let afterAll = Self(uncheckedRawValue: "after_all")
    public static let stateRead = Self(uncheckedRawValue: "state_read")
    public static let nextValue = Self(uncheckedRawValue: "next_value")
    public static let send = Self(uncheckedRawValue: "send")
    public static let receive = Self(uncheckedRawValue: "receive")

    public static let supportedCanonicalKinds: Set<Self> = [
        .literal,
        .identity,
        .add,
        .subtract,
        .bitwiseAnd,
        .bitwiseOr,
        .bitwiseXor,
        .concatenate,
        .tuple,
        .tupleIndex,
        .afterAll,
        .stateRead,
        .nextValue,
        .send,
        .receive,
    ]
}
