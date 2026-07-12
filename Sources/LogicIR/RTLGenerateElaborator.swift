import Foundation

public struct RTLGenerateElaborator: Sendable {
    public init() {}

    public func elaborate(_ design: RTLDesign) -> RTLDesign {
        var result = design
        result.modules = design.modules.map { module in
            var expanded = module
            expanded.generateBlocks = []
            let parameters = Dictionary(uniqueKeysWithValues: module.parameters.map { ($0.name, $0.value) })
            for block in module.generateBlocks {
                if block.kind == .conditional {
                    guard let condition = block.condition,
                          let value = evaluate(condition, parameters: parameters),
                          value != 0 else {
                        continue
                    }
                    appendConditionalBody(
                        block,
                        to: &expanded,
                        moduleName: module.name
                    )
                    continue
                }

                guard block.step != 0 else { continue }
                var value = block.start
                var iteration = 0
                while block.step > 0 ? value < block.limit : value > block.limit {
                    for instance in block.instances {
                        var copy = instance
                        copy.instanceName = "\(block.label)[\(iteration)].\(instance.instanceName)"
                        copy.id = StableLogicID.make(
                            kind: "generated-instance",
                            path: module.name,
                            name: "\(block.label)[\(iteration)].\(instance.instanceName)"
                        )
                        copy.connections = copy.connections.map { connection in
                            var connection = connection
                            connection.expression = replacing(
                                connection.expression,
                                identifier: block.loopVariable,
                                with: .integer(value: value, width: nil, isSigned: true)
                            )
                            return connection
                        }
                        expanded.instances.append(copy)
                    }
                    for assignment in block.assignments {
                        var copy = assignment
                        copy.id = StableLogicID.make(
                            kind: "generated-assignment",
                            path: module.name,
                            name: "\(block.label)[\(iteration)].\(assignment.id)"
                        )
                        copy.target = replacing(copy.target, identifier: block.loopVariable, with: .integer(value: value, width: nil, isSigned: true))
                        copy.value = replacing(copy.value, identifier: block.loopVariable, with: .integer(value: value, width: nil, isSigned: true))
                        expanded.assignments.append(copy)
                    }
                    value += block.step
                    iteration += 1
                }
            }
            return expanded
        }
        return result
    }

    private func appendConditionalBody(
        _ block: RTLGenerateBlock,
        to module: inout RTLModule,
        moduleName: String
    ) {
        for instance in block.instances {
            var copy = instance
            copy.instanceName = "\(block.label).\(instance.instanceName)"
            copy.id = StableLogicID.make(
                kind: "generated-instance",
                path: moduleName,
                name: copy.instanceName
            )
            module.instances.append(copy)
        }
        for assignment in block.assignments {
            var copy = assignment
            copy.id = StableLogicID.make(
                kind: "generated-assignment",
                path: moduleName,
                name: "\(block.label).\(assignment.id)"
            )
            module.assignments.append(copy)
        }
    }

    private func evaluate(
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
            case "-": return -value
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
            case "+": return lhs + rhs
            case "-": return lhs - rhs
            case "*": return lhs * rhs
            case "/": return rhs == 0 ? nil : lhs / rhs
            case "%": return rhs == 0 ? nil : lhs % rhs
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
            case "<<": return lhs << rhs
            case ">>": return lhs >> rhs
            default: return nil
            }
        case .ternary(let condition, let ifTrue, let ifFalse):
            guard let value = evaluate(condition, parameters: parameters) else { return nil }
            return evaluate(value != 0 ? ifTrue : ifFalse, parameters: parameters)
        case .string, .concatenate, .index, .partSelect:
            return nil
        }
    }

    private func replacing(
        _ expression: RTLExpression,
        identifier: String,
        with replacement: RTLExpression
    ) -> RTLExpression {
        switch expression {
        case .identifier(let name): return name == identifier ? replacement : expression
        case .integer, .string: return expression
        case .unary(let operation, let operand):
            return .unary(operator: operation, operand: replacing(operand, identifier: identifier, with: replacement))
        case .binary(let operation, let left, let right):
            return .binary(
                operator: operation,
                left: replacing(left, identifier: identifier, with: replacement),
                right: replacing(right, identifier: identifier, with: replacement)
            )
        case .ternary(let condition, let ifTrue, let ifFalse):
            return .ternary(
                condition: replacing(condition, identifier: identifier, with: replacement),
                ifTrue: replacing(ifTrue, identifier: identifier, with: replacement),
                ifFalse: replacing(ifFalse, identifier: identifier, with: replacement)
            )
        case .concatenate(let values):
            return .concatenate(values.map { replacing($0, identifier: identifier, with: replacement) })
        case .index(let value, let index):
            return .index(
                value: replacing(value, identifier: identifier, with: replacement),
                index: replacing(index, identifier: identifier, with: replacement)
            )
        case .partSelect(let value, let msb, let lsb):
            return .partSelect(
                value: replacing(value, identifier: identifier, with: replacement),
                msb: replacing(msb, identifier: identifier, with: replacement),
                lsb: replacing(lsb, identifier: identifier, with: replacement)
            )
        }
    }
}
