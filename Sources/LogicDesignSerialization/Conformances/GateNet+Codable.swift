import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension GateNet: Codable {
    private enum CodingKeys: String, CodingKey { case `id`, `name`, `width`, `driverPinIDs`, `loadPinIDs`, `source` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .`id`)
        let name = try container.decode(String.self, forKey: .`name`)
        let width = try container.decode(Int.self, forKey: .`width`)
        let driverPinIDs = try container.decode([String].self, forKey: .`driverPinIDs`)
        let loadPinIDs = try container.decode([String].self, forKey: .`loadPinIDs`)
        let source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .`source`)
        self.init(id: id, name: name, width: width, driverPinIDs: driverPinIDs, loadPinIDs: loadPinIDs, source: source)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .`id`)
        try container.encode(name, forKey: .`name`)
        try container.encode(width, forKey: .`width`)
        try container.encode(driverPinIDs, forKey: .`driverPinIDs`)
        try container.encode(loadPinIDs, forKey: .`loadPinIDs`)
        try container.encodeIfPresent(source, forKey: .`source`)
    }
}
