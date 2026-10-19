import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension RTLPortConnection: Codable {
    private enum CodingKeys: String, CodingKey { case `portName`, `expression`, `source` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let portName = try container.decode(String.self, forKey: .`portName`)
        let expression = try container.decode(RTLExpression.self, forKey: .`expression`)
        let source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .`source`)
        self.init(portName: portName, expression: expression, source: source)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(portName, forKey: .`portName`)
        try container.encode(expression, forKey: .`expression`)
        try container.encodeIfPresent(source, forKey: .`source`)
    }
}
