import Foundation

public struct RTLPortConnection: Sendable, Hashable, Codable {
    public var portName: String
    public var expression: RTLExpression
    public var source: LogicSourceSpan?

    public init(portName: String, expression: RTLExpression, source: LogicSourceSpan? = nil) {
        self.portName = portName
        self.expression = expression
        self.source = source
    }
}
