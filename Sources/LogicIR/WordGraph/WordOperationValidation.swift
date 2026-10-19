import LogicKernelCore

internal enum WordOperationValidation {
    static func validate(_ opcode: WordLogicOpcode, result: WordLogicType, operandCount: Int,
                         typeAt: (Int) -> WordLogicType, context: inout LogicKernelContext) throws(LogicKernelError) {
        if let count = opcode.fixedOperandCount {
            guard operandCount == count else { throw .invalidModel("Word opcode arity mismatch") }
        } else if operandCount == 0 { throw .invalidModel("Empty concatenation") }
        let first = typeAt(0)
        let firstWidth = first.width.value
        let width = result.width.value
        let booleanResult = width == 1 && !result.isSigned
        switch opcode {
        case .bitcast:
            guard width == firstWidth else { throw .invalidModel("Bitcast changes width") }
        case .zeroExtend:
            guard width >= firstWidth else { throw .invalidModel("Zero extension narrows") }
        case .signExtend:
            guard width >= firstWidth, first.isSigned else { throw .invalidModel("Invalid sign extension") }
        case .slice(let offset):
            guard offset >= 0, width <= firstWidth, offset <= firstWidth - width, !result.isSigned else {
                throw .invalidModel("Invalid slice range or signedness")
            }
        case .concatenate:
            var total = 0
            for offset in 0..<operandCount {
                try context.charge(.workUnits)
                let sum = total.addingReportingOverflow(typeAt(offset).width.value)
                guard !sum.overflow else { throw .invalidModel("Concatenation width overflow") }
                total = sum.partialValue
            }
            guard width == total, !result.isSigned else { throw .invalidModel("Concatenation type mismatch") }
        case .logicalNot, .logicalAnd, .logicalOr, .reduceAnd, .reduceOr, .reduceXor:
            guard booleanResult else { throw .invalidModel("Boolean result must be unsigned one-bit") }
        case .equal, .lessThan:
            let second = typeAt(1)
            guard first == second, booleanResult else { throw .invalidModel("Comparison type mismatch") }
        case .shiftLeft, .shiftRight:
            let second = typeAt(1)
            guard first == result, !second.isSigned else { throw .invalidModel("Shift operands must be explicitly resolved") }
        case .select:
            guard firstWidth == 1, !first.isSigned else { throw .invalidModel("Select condition must be unsigned one-bit") }
            for offset in 1..<operandCount {
                guard typeAt(offset) == result else { throw .invalidModel("Select branch type mismatch") }
            }
        case .invert, .negate, .and, .or, .xor, .add, .subtract, .multiply:
            for offset in 0..<operandCount {
                guard typeAt(offset) == result else { throw .invalidModel("Arithmetic or bitwise type mismatch") }
            }
        }
    }
}
