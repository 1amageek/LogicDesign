import Foundation

public struct GateModule: Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    public var ports: [RTLPort]
    public var portBindings: [GatePortBinding]?
    public var cells: [GateCell]
    public var nets: [GateNet]
    public var source: LogicSourceSpan?

    public init(
        id: String,
        name: String,
        ports: [RTLPort] = [],
        portBindings: [GatePortBinding]? = nil,
        cells: [GateCell] = [],
        nets: [GateNet] = [],
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.name = name
        self.ports = ports
        self.portBindings = portBindings
        self.cells = cells
        self.nets = nets
        self.source = source
    }
}
