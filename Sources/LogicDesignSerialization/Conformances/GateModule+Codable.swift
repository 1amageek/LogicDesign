import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension GateModule: Codable {
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
        let id = try container.decode(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let ports = try container.decode([RTLPort].self, forKey: .ports)
        let cells = try container.decode([GateCell].self, forKey: .cells)
        let nets = try container.decode([GateNet].self, forKey: .nets)
        let source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .source)
        let portBindings = try container.decode([GatePortBinding].self, forKey: .portBindings)
        self.init(id: id, name: name, ports: ports, portBindings: portBindings, cells: cells, nets: nets, source: source)
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
}
