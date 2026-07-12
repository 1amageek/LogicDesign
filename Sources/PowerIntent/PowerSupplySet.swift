import Foundation
import LogicIR

public struct PowerSupplySet: Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    public var supplyNets: [String]
    public var source: LogicSourceSpan?

    public init(id: String, name: String, supplyNets: [String] = [], source: LogicSourceSpan? = nil) {
        self.id = id
        self.name = name
        self.supplyNets = supplyNets
        self.source = source
    }
}
