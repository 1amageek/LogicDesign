import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension RTLStatement: Codable {
    private enum CaseKey: String, CodingKey { case `assignment`, `block`, `conditional`, `typedCaseStatement`, `null` }
    private enum PayloadKey: String, CodingKey { case `_0`, `condition`, `ifTrue`, `ifFalse`, `kind`, `expression`, `items`, `defaultStatements` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CaseKey.self)
        guard container.allKeys.count == 1, let selected = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected one enum case"))
        }
        switch selected {
        case .`assignment`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`assignment`)
            self = .assignment(try payload.decode(RTLAssignment.self, forKey: .`_0`))
        case .`block`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`block`)
            self = .block(try payload.decode([RTLStatement].self, forKey: .`_0`))
        case .`conditional`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`conditional`)
            self = .conditional(condition: try payload.decode(RTLExpression.self, forKey: .`condition`), ifTrue: try payload.decode([RTLStatement].self, forKey: .`ifTrue`), ifFalse: try payload.decode([RTLStatement].self, forKey: .`ifFalse`))
        case .`typedCaseStatement`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`typedCaseStatement`)
            self = .typedCaseStatement(kind: try payload.decode(RTLCaseKind.self, forKey: .`kind`), expression: try payload.decode(RTLExpression.self, forKey: .`expression`), items: try payload.decode([RTLCaseItem].self, forKey: .`items`), defaultStatements: try payload.decode([RTLStatement].self, forKey: .`defaultStatements`))
        case .`null`:
            _ = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`null`)
            self = .null
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CaseKey.self)
        switch self {
        case .assignment(let value0):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`assignment`)
            try payload.encode(value0, forKey: .`_0`)
        case .block(let value0):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`block`)
            try payload.encode(value0, forKey: .`_0`)
        case .conditional(let value0, let value1, let value2):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`conditional`)
            try payload.encode(value0, forKey: .`condition`)
            try payload.encode(value1, forKey: .`ifTrue`)
            try payload.encode(value2, forKey: .`ifFalse`)
        case .typedCaseStatement(let value0, let value1, let value2, let value3):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`typedCaseStatement`)
            try payload.encode(value0, forKey: .`kind`)
            try payload.encode(value1, forKey: .`expression`)
            try payload.encode(value2, forKey: .`items`)
            try payload.encode(value3, forKey: .`defaultStatements`)
        case .null:
            let payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`null`)
            _ = payload
        }
    }
}
