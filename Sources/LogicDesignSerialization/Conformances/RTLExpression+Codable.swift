import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension RTLExpression: Codable {
    private enum CaseKey: String, CodingKey { case `identifier`, `integer`, `string`, `unary`, `binary`, `ternary`, `concatenate`, `index`, `partSelect` }
    private enum PayloadKey: String, CodingKey { case `_0`, `value`, `width`, `isSigned`, `operator`, `operand`, `left`, `right`, `condition`, `ifTrue`, `ifFalse`, `index`, `msb`, `lsb` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CaseKey.self)
        guard container.allKeys.count == 1, let selected = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected one enum case"))
        }
        switch selected {
        case .`identifier`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`identifier`)
            self = .identifier(try payload.decode(String.self, forKey: .`_0`))
        case .`integer`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`integer`)
            self = .integer(value: try payload.decode(Int64.self, forKey: .`value`), width: try payload.decodeIfPresent(Int.self, forKey: .`width`), isSigned: try payload.decode(Bool.self, forKey: .`isSigned`))
        case .`string`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`string`)
            self = .string(try payload.decode(String.self, forKey: .`_0`))
        case .`unary`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`unary`)
            self = .unary(operator: try payload.decode(String.self, forKey: .`operator`), operand: try payload.decode(RTLExpression.self, forKey: .`operand`))
        case .`binary`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`binary`)
            self = .binary(operator: try payload.decode(String.self, forKey: .`operator`), left: try payload.decode(RTLExpression.self, forKey: .`left`), right: try payload.decode(RTLExpression.self, forKey: .`right`))
        case .`ternary`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`ternary`)
            self = .ternary(condition: try payload.decode(RTLExpression.self, forKey: .`condition`), ifTrue: try payload.decode(RTLExpression.self, forKey: .`ifTrue`), ifFalse: try payload.decode(RTLExpression.self, forKey: .`ifFalse`))
        case .`concatenate`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`concatenate`)
            self = .concatenate(try payload.decode([RTLExpression].self, forKey: .`_0`))
        case .`index`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`index`)
            self = .index(value: try payload.decode(RTLExpression.self, forKey: .`value`), index: try payload.decode(RTLExpression.self, forKey: .`index`))
        case .`partSelect`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`partSelect`)
            self = .partSelect(value: try payload.decode(RTLExpression.self, forKey: .`value`), msb: try payload.decode(RTLExpression.self, forKey: .`msb`), lsb: try payload.decode(RTLExpression.self, forKey: .`lsb`))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CaseKey.self)
        switch self {
        case .identifier(let value0):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`identifier`)
            try payload.encode(value0, forKey: .`_0`)
        case .integer(let value0, let value1, let value2):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`integer`)
            try payload.encode(value0, forKey: .`value`)
            try payload.encodeIfPresent(value1, forKey: .`width`)
            try payload.encode(value2, forKey: .`isSigned`)
        case .string(let value0):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`string`)
            try payload.encode(value0, forKey: .`_0`)
        case .unary(let value0, let value1):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`unary`)
            try payload.encode(value0, forKey: .`operator`)
            try payload.encode(value1, forKey: .`operand`)
        case .binary(let value0, let value1, let value2):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`binary`)
            try payload.encode(value0, forKey: .`operator`)
            try payload.encode(value1, forKey: .`left`)
            try payload.encode(value2, forKey: .`right`)
        case .ternary(let value0, let value1, let value2):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`ternary`)
            try payload.encode(value0, forKey: .`condition`)
            try payload.encode(value1, forKey: .`ifTrue`)
            try payload.encode(value2, forKey: .`ifFalse`)
        case .concatenate(let value0):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`concatenate`)
            try payload.encode(value0, forKey: .`_0`)
        case .index(let value0, let value1):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`index`)
            try payload.encode(value0, forKey: .`value`)
            try payload.encode(value1, forKey: .`index`)
        case .partSelect(let value0, let value1, let value2):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`partSelect`)
            try payload.encode(value0, forKey: .`value`)
            try payload.encode(value1, forKey: .`msb`)
            try payload.encode(value2, forKey: .`lsb`)
        }
    }
}
