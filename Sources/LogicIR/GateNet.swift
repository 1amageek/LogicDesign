import Foundation

public struct GateNet: Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    public var width: Int
    public var driverPinIDs: [String]
    public var loadPinIDs: [String]
    public var source: LogicSourceSpan?

    public init(
        id: String,
        name: String,
        width: Int = 1,
        driverPinIDs: [String] = [],
        loadPinIDs: [String] = [],
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.name = name
        self.width = width
        self.driverPinIDs = driverPinIDs
        self.loadPinIDs = loadPinIDs
        self.source = source
    }
}
