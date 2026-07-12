import Foundation
import LogicIR

public struct PowerDomain: Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    public var elements: [String]
    public var primarySupplySet: String?
    public var primarySupplyNet: String?
    public var source: LogicSourceSpan?

    public init(
        id: String,
        name: String,
        elements: [String] = [],
        primarySupplySet: String? = nil,
        primarySupplyNet: String? = nil,
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.name = name
        self.elements = elements
        self.primarySupplySet = primarySupplySet
        self.primarySupplyNet = primarySupplyNet
        self.source = source
    }
}
