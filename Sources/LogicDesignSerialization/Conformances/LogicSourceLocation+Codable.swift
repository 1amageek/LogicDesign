import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicSourceLocation: Codable {
    private enum CodingKeys: String, CodingKey { case `path`, `line`, `column`, `offset` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let path = try container.decode(String.self, forKey: .`path`)
        let line = try container.decode(Int.self, forKey: .`line`)
        let column = try container.decode(Int.self, forKey: .`column`)
        let offset = try container.decode(Int.self, forKey: .`offset`)
        self.init(path: path, line: line, column: column, offset: offset)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .`path`)
        try container.encode(line, forKey: .`line`)
        try container.encode(column, forKey: .`column`)
        try container.encode(offset, forKey: .`offset`)
    }
}
