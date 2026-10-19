public struct RTLProcess: Sendable, Hashable {
    public var id: String
    public var kind: RTLProcessKind
    public var sensitivity: [String]
    public var clockEdge: RTLClockEdge?
    public var events: [RTLProcessEvent]
    public var statements: [RTLStatement]
    public var source: LogicSourceSpan?

    public init(
        id: String,
        kind: RTLProcessKind,
        sensitivity: [String] = [],
        clockEdge: RTLClockEdge? = nil,
        events: [RTLProcessEvent] = [],
        statements: [RTLStatement] = [],
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sensitivity = sensitivity
        self.clockEdge = clockEdge
        self.events = events
        self.statements = statements
        self.source = source
    }

}
