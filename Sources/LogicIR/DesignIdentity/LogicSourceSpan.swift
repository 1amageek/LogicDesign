public struct LogicSourceSpan: Sendable, Hashable {
    public var start: LogicSourceLocation
    public var end: LogicSourceLocation

    public init(start: LogicSourceLocation, end: LogicSourceLocation) {
        self.start = start
        self.end = end
    }
}
