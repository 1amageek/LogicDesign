import Foundation

public struct RTLMemory: Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    public var elementRange: LogicRange?
    public var addressRange: LogicRange
    public var source: LogicSourceSpan?

    public init(
        id: String,
        name: String,
        elementRange: LogicRange?,
        addressRange: LogicRange,
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.name = name
        self.elementRange = elementRange
        self.addressRange = addressRange
        self.source = source
    }
}
