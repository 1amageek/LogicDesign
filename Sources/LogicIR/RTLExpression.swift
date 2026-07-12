import Foundation

public indirect enum RTLExpression: Sendable, Hashable, Codable {
    case identifier(String)
    case integer(value: Int64, width: Int?, isSigned: Bool)
    case string(String)
    case unary(operator: String, operand: RTLExpression)
    case binary(operator: String, left: RTLExpression, right: RTLExpression)
    case ternary(condition: RTLExpression, ifTrue: RTLExpression, ifFalse: RTLExpression)
    case concatenate([RTLExpression])
    case index(value: RTLExpression, index: RTLExpression)
    case partSelect(value: RTLExpression, msb: RTLExpression, lsb: RTLExpression)
}
