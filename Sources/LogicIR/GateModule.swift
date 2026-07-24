import Foundation

public struct GateModule: Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    public var ports: [RTLPort]
    public var portBindings: [GatePortBinding]
    public var cells: [GateCell]
    public var nets: [GateNet]
    public var source: LogicSourceSpan?

    public init(
        id: String,
        name: String,
        ports: [RTLPort] = [],
        portBindings: [GatePortBinding] = [],
        cells: [GateCell] = [],
        nets: [GateNet] = [],
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.name = name
        self.ports = ports
        self.cells = cells
        self.nets = nets
        self.source = source
        self.portBindings = portBindings
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case ports
        case portBindings
        case cells
        case nets
        case source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        ports = try container.decode([RTLPort].self, forKey: .ports)
        cells = try container.decode([GateCell].self, forKey: .cells)
        nets = try container.decode([GateNet].self, forKey: .nets)
        source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .source)
        portBindings = try container.decodeIfPresent(
            [GatePortBinding].self,
            forKey: .portBindings
        ) ?? Self.migratedPortBindings(ports: ports, nets: nets)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(ports, forKey: .ports)
        try container.encode(portBindings, forKey: .portBindings)
        try container.encode(cells, forKey: .cells)
        try container.encode(nets, forKey: .nets)
        try container.encodeIfPresent(source, forKey: .source)
    }

    private static func migratedPortBindings(
        ports: [RTLPort],
        nets: [GateNet]
    ) -> [GatePortBinding] {
        ports.compactMap { port in
            let candidates = nets.filter {
                $0.name == port.name || $0.id == port.name
            }
            guard candidates.count == 1, let net = candidates.first else {
                return nil
            }
            return GatePortBinding(portID: port.id, netID: net.id)
        }
    }
}
