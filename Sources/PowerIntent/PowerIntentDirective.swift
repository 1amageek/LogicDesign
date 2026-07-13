import Foundation
import LogicIR

public struct PowerIntentDirective: Sendable, Hashable, Codable {
    public var id: String
    public var command: String
    public var arguments: [String]
    public var options: [String: String]
    public var source: LogicSourceSpan?

    public init(
        id: String,
        command: String,
        arguments: [String] = [],
        options: [String: String] = [:],
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.command = command
        self.arguments = arguments
        self.options = options
        self.source = source
    }
}
