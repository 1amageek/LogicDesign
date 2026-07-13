import Foundation

public struct RTLMemory: Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    public var elementRange: LogicRange?
    public var elementRangeExpression: RTLRangeExpression?
    public var addressRange: LogicRange
    public var addressRangeExpression: RTLRangeExpression?
    public var source: LogicSourceSpan?

    public init(
        id: String,
        name: String,
        elementRange: LogicRange?,
        addressRange: LogicRange,
        elementRangeExpression: RTLRangeExpression? = nil,
        addressRangeExpression: RTLRangeExpression? = nil,
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.name = name
        self.elementRange = elementRange
        self.elementRangeExpression = elementRangeExpression
        self.addressRange = addressRange
        self.addressRangeExpression = addressRangeExpression
        self.source = source
    }
}
