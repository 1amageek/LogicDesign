import Foundation

public struct RTLSignal: Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    public var dataType: LogicDataType
    public var storage: LogicStorageKind
    public var range: LogicRange?
    public var isSigned: Bool
    public var source: LogicSourceSpan?

    public init(
        id: String,
        name: String,
        dataType: LogicDataType = .logic,
        storage: LogicStorageKind = .combinational,
        range: LogicRange? = nil,
        isSigned: Bool = false,
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.name = name
        self.dataType = dataType
        self.storage = storage
        self.range = range
        self.isSigned = isSigned
        self.source = source
    }
}
