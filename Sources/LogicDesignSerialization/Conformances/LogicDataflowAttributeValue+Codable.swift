import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicDataflowAttributeValue: Codable {
    private enum CaseKey: String, CodingKey { case `integer`, `unsignedInteger`, `boolean`, `identifier`, `identifiers`, `text`, `literal` }
    private enum PayloadKey: String, CodingKey { case `_0` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CaseKey.self)
        guard container.allKeys.count == 1, let selected = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected one enum case"))
        }
        switch selected {
        case .`integer`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`integer`)
            self = .integer(try payload.decode(Int64.self, forKey: .`_0`))
        case .`unsignedInteger`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`unsignedInteger`)
            self = .unsignedInteger(try payload.decode(UInt64.self, forKey: .`_0`))
        case .`boolean`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`boolean`)
            self = .boolean(try payload.decode(Bool.self, forKey: .`_0`))
        case .`identifier`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`identifier`)
            self = .identifier(try payload.decode(String.self, forKey: .`_0`))
        case .`identifiers`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`identifiers`)
            self = .identifiers(try payload.decode([String].self, forKey: .`_0`))
        case .`text`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`text`)
            self = .text(try payload.decode(String.self, forKey: .`_0`))
        case .`literal`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`literal`)
            self = .literal(try payload.decode(LogicDataflowValue.self, forKey: .`_0`))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CaseKey.self)
        switch self {
        case .integer(let value0):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`integer`)
            try payload.encode(value0, forKey: .`_0`)
        case .unsignedInteger(let value0):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`unsignedInteger`)
            try payload.encode(value0, forKey: .`_0`)
        case .boolean(let value0):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`boolean`)
            try payload.encode(value0, forKey: .`_0`)
        case .identifier(let value0):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`identifier`)
            try payload.encode(value0, forKey: .`_0`)
        case .identifiers(let value0):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`identifiers`)
            try payload.encode(value0, forKey: .`_0`)
        case .text(let value0):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`text`)
            try payload.encode(value0, forKey: .`_0`)
        case .literal(let value0):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`literal`)
            try payload.encode(value0, forKey: .`_0`)
        }
    }
}
