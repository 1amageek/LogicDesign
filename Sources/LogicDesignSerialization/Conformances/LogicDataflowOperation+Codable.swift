import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicDataflowOperation: Codable {
    private enum CodingKeys: String, CodingKey { case `kind`, `operands`, `attributes` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(LogicDataflowOperationKind.self, forKey: .`kind`)
        let operands = try container.decode([String].self, forKey: .`operands`)
        let attributes = try container.decode([LogicDataflowAttribute].self, forKey: .`attributes`)
        self.init(kind: kind, operands: operands, attributes: attributes)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .`kind`)
        try container.encode(operands, forKey: .`operands`)
        try container.encode(attributes, forKey: .`attributes`)
    }
}
