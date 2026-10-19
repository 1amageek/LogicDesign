import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension RTLPort: Codable {
    private enum CodingKeys: String, CodingKey { case `id`, `name`, `direction`, `dataType`, `range`, `rangeExpression`, `isSigned`, `source` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .`id`)
        let name = try container.decode(String.self, forKey: .`name`)
        let direction = try container.decode(LogicDirection.self, forKey: .`direction`)
        let dataType = try container.decode(LogicDataType.self, forKey: .`dataType`)
        let range = try container.decodeIfPresent(LogicRange.self, forKey: .`range`)
        let rangeExpression = try container.decodeIfPresent(RTLRangeExpression.self, forKey: .`rangeExpression`)
        let isSigned = try container.decode(Bool.self, forKey: .`isSigned`)
        let source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .`source`)
        self.init(id: id, name: name, direction: direction, dataType: dataType, range: range, rangeExpression: rangeExpression, isSigned: isSigned, source: source)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .`id`)
        try container.encode(name, forKey: .`name`)
        try container.encode(direction, forKey: .`direction`)
        try container.encode(dataType, forKey: .`dataType`)
        try container.encodeIfPresent(range, forKey: .`range`)
        try container.encodeIfPresent(rangeExpression, forKey: .`rangeExpression`)
        try container.encode(isSigned, forKey: .`isSigned`)
        try container.encodeIfPresent(source, forKey: .`source`)
    }
}
