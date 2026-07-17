import Foundation

public indirect enum RTLStatement: Sendable, Hashable, Codable {
    case assignment(RTLAssignment)
    case block([RTLStatement])
    case conditional(condition: RTLExpression, ifTrue: [RTLStatement], ifFalse: [RTLStatement])
    /// Legacy compatibility case. New producers must use the typed case form.
    case caseStatement(expression: RTLExpression, items: [RTLCaseItem], defaultStatements: [RTLStatement])
    case typedCaseStatement(kind: RTLCaseKind, expression: RTLExpression, items: [RTLCaseItem], defaultStatements: [RTLStatement])
    case null
}
