import Foundation

public struct LogicSourceSpan: Sendable, Hashable, Codable {
    public var start: LogicSourceLocation
    public var end: LogicSourceLocation

    public init(start: LogicSourceLocation, end: LogicSourceLocation) {
        self.start = start
        self.end = end
    }
}
