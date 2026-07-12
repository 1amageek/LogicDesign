import Foundation

public struct RTLPort: Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    public var direction: LogicDirection
    public var dataType: LogicDataType
    public var range: LogicRange?
    public var isSigned: Bool
    public var source: LogicSourceSpan?

    public init(
        id: String,
        name: String,
        direction: LogicDirection,
        dataType: LogicDataType = .logic,
        range: LogicRange? = nil,
        isSigned: Bool = false,
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.name = name
        self.direction = direction
        self.dataType = dataType
        self.range = range
        self.isSigned = isSigned
        self.source = source
    }
}
