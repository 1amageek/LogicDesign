import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicSourceSpan: Codable {
    private enum CodingKeys: String, CodingKey { case `start`, `end` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let start = try container.decode(LogicSourceLocation.self, forKey: .`start`)
        let end = try container.decode(LogicSourceLocation.self, forKey: .`end`)
        self.init(start: start, end: end)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .`start`)
        try container.encode(end, forKey: .`end`)
    }
}
