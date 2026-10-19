import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicDataflowType: Codable {
    private enum CaseKey: String, CodingKey { case `bits`, `tuple`, `array`, `token` }
    private enum PayloadKey: String, CodingKey { case `width`, `_0`, `element`, `count` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CaseKey.self)
        guard container.allKeys.count == 1, let selected = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected one enum case"))
        }
        switch selected {
        case .`bits`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`bits`)
            self = .bits(width: try payload.decode(Int.self, forKey: .`width`))
        case .`tuple`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`tuple`)
            self = .tuple(try payload.decode([LogicDataflowType].self, forKey: .`_0`))
        case .`array`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`array`)
            self = .array(element: try payload.decode(LogicDataflowType.self, forKey: .`element`), count: try payload.decode(Int.self, forKey: .`count`))
        case .`token`:
            _ = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`token`)
            self = .token
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CaseKey.self)
        switch self {
        case .bits(let value0):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`bits`)
            try payload.encode(value0, forKey: .`width`)
        case .tuple(let value0):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`tuple`)
            try payload.encode(value0, forKey: .`_0`)
        case .array(let value0, let value1):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`array`)
            try payload.encode(value0, forKey: .`element`)
            try payload.encode(value1, forKey: .`count`)
        case .token:
            let payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`token`)
            _ = payload
        }
    }
}
