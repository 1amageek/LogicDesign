import Foundation

public indirect enum RTLStatement: Sendable, Hashable, Codable {
    case assignment(RTLAssignment)
    case block([RTLStatement])
    case conditional(condition: RTLExpression, ifTrue: [RTLStatement], ifFalse: [RTLStatement])
    case typedCaseStatement(kind: RTLCaseKind, expression: RTLExpression, items: [RTLCaseItem], defaultStatements: [RTLStatement])
    case null
}
