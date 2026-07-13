import Foundation

/// Evaluates the constant expression subset used by parameters, ranges, and generate blocks.
public struct RTLConstantEvaluator: Sendable {
    public init() {}

    public func evaluate(
        _ expression: RTLExpression,
        parameters: [String: Int64]
    ) -> Int64? {
        switch expression {
        case .identifier(let name):
            return parameters[name]
        case .integer(let value, _, _):
            return value
        case .unary(let operation, let operand):
            guard let value = evaluate(operand, parameters: parameters) else { return nil }
            switch operation {
            case "+": return value
            case "-":
                guard value != Int64.min else { return nil }
                return -value
            case "!": return value == 0 ? 1 : 0
            case "~": return ~value
            default: return nil
            }
        case .binary(let operation, let left, let right):
            guard let lhs = evaluate(left, parameters: parameters),
                  let rhs = evaluate(right, parameters: parameters) else {
                return nil
            }
            switch operation {
            case "+": return checkedAdd(lhs, rhs)
            case "-": return checkedSubtract(lhs, rhs)
            case "*": return checkedMultiply(lhs, rhs)
            case "/":
                guard rhs != 0, !(lhs == Int64.min && rhs == -1) else { return nil }
                return lhs / rhs
            case "%":
                guard rhs != 0, !(lhs == Int64.min && rhs == -1) else { return nil }
                return lhs % rhs
            case "&": return lhs & rhs
            case "|": return lhs | rhs
            case "^": return lhs ^ rhs
            case "&&": return lhs != 0 && rhs != 0 ? 1 : 0
            case "||": return lhs != 0 || rhs != 0 ? 1 : 0
            case "==", "===": return lhs == rhs ? 1 : 0
            case "!=", "!==": return lhs != rhs ? 1 : 0
            case "<": return lhs < rhs ? 1 : 0
            case ">": return lhs > rhs ? 1 : 0
            case "<=": return lhs <= rhs ? 1 : 0
            case ">=": return lhs >= rhs ? 1 : 0
            case "<<":
                guard rhs >= 0, rhs < 64 else { return nil }
                return lhs << rhs
            case ">>":
                guard rhs >= 0, rhs < 64 else { return nil }
                return lhs >> rhs
            default: return nil
            }
        case .ternary(let condition, let ifTrue, let ifFalse):
            guard let value = evaluate(condition, parameters: parameters) else { return nil }
            return evaluate(value != 0 ? ifTrue : ifFalse, parameters: parameters)
        case .string, .concatenate, .index, .partSelect:
            return nil
        }
    }

    private func checkedAdd(_ lhs: Int64, _ rhs: Int64) -> Int64? {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? nil : result.partialValue
    }

    private func checkedSubtract(_ lhs: Int64, _ rhs: Int64) -> Int64? {
        let result = lhs.subtractingReportingOverflow(rhs)
        return result.overflow ? nil : result.partialValue
    }

    private func checkedMultiply(_ lhs: Int64, _ rhs: Int64) -> Int64? {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        return result.overflow ? nil : result.partialValue
    }
}
