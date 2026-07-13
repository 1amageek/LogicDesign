import Foundation

public struct RTLGenerateElaborator: Sendable {
    private let evaluator: RTLConstantEvaluator

    public init(evaluator: RTLConstantEvaluator = RTLConstantEvaluator()) {
        self.evaluator = evaluator
    }

    public func elaborate(_ design: RTLDesign) -> RTLDesign {
        var result = design
        result.modules = design.modules.map { module in
            elaborate(module, parameterValues: defaultParameterValues(for: module))
        }
        return result
    }

    /// Expands a single module using the parameter context of one hierarchy instance.
    public func elaborate(
        _ module: RTLModule,
        parameterValues: [String: Int64]
    ) -> RTLModule {
        var expanded = module
        expanded.generateBlocks = []
        let parameterExpressions = parameterValues.mapValues {
            RTLExpression.integer(value: $0, width: nil, isSigned: true)
        }

        for block in module.generateBlocks {
            if block.kind == .conditional {
                guard let condition = block.condition,
                      let value = evaluator.evaluate(condition, parameters: parameterValues),
                      value != 0 else {
                    continue
                }
                appendConditionalBody(
                    block,
                    to: &expanded,
                    moduleName: module.name,
                    replacements: parameterExpressions
                )
                continue
            }

            let start = evaluator.evaluate(
                block.startExpression ?? .integer(value: block.start, width: nil, isSigned: true),
                parameters: parameterValues
            ) ?? block.start
            let limit = evaluator.evaluate(
                block.limitExpression ?? .integer(value: block.limit, width: nil, isSigned: true),
                parameters: parameterValues
            ) ?? block.limit
            let step = evaluator.evaluate(
                block.stepExpression ?? .integer(value: block.step, width: nil, isSigned: true),
                parameters: parameterValues
            ) ?? block.step
            guard step != 0 else { continue }

            var value = start
            var iteration = 0
            while step > 0 ? value < limit : value > limit {
                var replacements = parameterExpressions
                replacements[block.loopVariable] = .integer(
                    value: value,
                    width: nil,
                    isSigned: true
                )
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
                            identifiers: replacements
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
                    copy.target = replacing(copy.target, identifiers: replacements)
                    copy.value = replacing(copy.value, identifiers: replacements)
                    expanded.assignments.append(copy)
                }
                let next = value.addingReportingOverflow(step)
                guard !next.overflow else { break }
                value = next.partialValue
                iteration += 1
            }
        }
        return expanded
    }

    private func appendConditionalBody(
        _ block: RTLGenerateBlock,
        to module: inout RTLModule,
        moduleName: String,
        replacements: [String: RTLExpression]
    ) {
        for instance in block.instances {
            var copy = instance
            copy.instanceName = "\(block.label).\(instance.instanceName)"
            copy.id = StableLogicID.make(
                kind: "generated-instance",
                path: moduleName,
                name: copy.instanceName
            )
            copy.connections = copy.connections.map { connection in
                var connection = connection
                connection.expression = replacing(connection.expression, identifiers: replacements)
                return connection
            }
            module.instances.append(copy)
        }
        for assignment in block.assignments {
            var copy = assignment
            copy.id = StableLogicID.make(
                kind: "generated-assignment",
                path: moduleName,
                name: "\(block.label).\(assignment.id)"
            )
            copy.target = replacing(copy.target, identifiers: replacements)
            copy.value = replacing(copy.value, identifiers: replacements)
            module.assignments.append(copy)
        }
    }

    private func defaultParameterValues(for module: RTLModule) -> [String: Int64] {
        var values: [String: Int64] = [:]
        for parameter in module.parameters {
            let expression = parameter.defaultExpression ?? .integer(
                value: parameter.value,
                width: nil,
                isSigned: true
            )
            values[parameter.name] = evaluator.evaluate(expression, parameters: values) ?? parameter.value
        }
        return values
    }

    private func replacing(
        _ expression: RTLExpression,
        identifiers: [String: RTLExpression]
    ) -> RTLExpression {
        switch expression {
        case .identifier(let name):
            return identifiers[name] ?? expression
        case .integer, .string:
            return expression
        case .unary(let operation, let operand):
            return .unary(
                operator: operation,
                operand: replacing(operand, identifiers: identifiers)
            )
        case .binary(let operation, let left, let right):
            return .binary(
                operator: operation,
                left: replacing(left, identifiers: identifiers),
                right: replacing(right, identifiers: identifiers)
            )
        case .ternary(let condition, let ifTrue, let ifFalse):
            return .ternary(
                condition: replacing(condition, identifiers: identifiers),
                ifTrue: replacing(ifTrue, identifiers: identifiers),
                ifFalse: replacing(ifFalse, identifiers: identifiers)
            )
        case .concatenate(let values):
            return .concatenate(values.map { replacing($0, identifiers: identifiers) })
        case .index(let value, let index):
            return .index(
                value: replacing(value, identifiers: identifiers),
                index: replacing(index, identifiers: identifiers)
            )
        case .partSelect(let value, let msb, let lsb):
            return .partSelect(
                value: replacing(value, identifiers: identifiers),
                msb: replacing(msb, identifiers: identifiers),
                lsb: replacing(lsb, identifiers: identifiers)
            )
        }
    }
}
