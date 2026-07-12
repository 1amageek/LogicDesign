import Foundation

public struct RTLProcess: Sendable, Hashable, Codable {
    public var id: String
    public var kind: RTLProcessKind
    public var sensitivity: [String]
    public var clockEdge: RTLClockEdge?
    public var statements: [RTLStatement]
    public var source: LogicSourceSpan?

    public init(
        id: String,
        kind: RTLProcessKind,
        sensitivity: [String] = [],
        clockEdge: RTLClockEdge? = nil,
        statements: [RTLStatement] = [],
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sensitivity = sensitivity
        self.clockEdge = clockEdge
        self.statements = statements
        self.source = source
    }
}
