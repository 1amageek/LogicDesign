import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension RTLCaseItem: Codable {
    private enum CodingKeys: String, CodingKey { case `matches`, `statements`, `source` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let matches = try container.decode([RTLExpression].self, forKey: .`matches`)
        let statements = try container.decode([RTLStatement].self, forKey: .`statements`)
        let source = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .`source`)
        self.init(matches: matches, statements: statements, source: source)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(matches, forKey: .`matches`)
        try container.encode(statements, forKey: .`statements`)
        try container.encodeIfPresent(source, forKey: .`source`)
    }
}
