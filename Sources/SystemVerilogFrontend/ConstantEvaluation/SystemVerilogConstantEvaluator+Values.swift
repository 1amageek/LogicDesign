import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogConstantEvaluator {
    internal mutating func evaluateExpression(_ root: Int, width: Int, signed: Bool,
        context: inout LogicKernelContext) throws(LogicKernelError) -> LogicFourStateVector {
        if try metadata(root).containsRuntime {
            throw try failure(root,"SV_EXPRESSION_CONSTANT_REQUIRED","A runtime-dependent expression cannot be evaluated as a constant")
        }
        guard frames.isEmpty && values.isEmpty else { throw .invalidModel("Constant evaluation cannot reenter its workspace") }
        frames.append(Frame(node: root, width: width, signed: signed, finish: false))
        while let frame = frames.popLast() {
            try context.charge(.workUnits)
            let metadata = try metadata(frame.node)
            let kind = try syntax.node(at: frame.node).kind
            let count: Int
            switch kind {
            case .repeated, .select: count = 1
            case .concatenate(let range):
                var nonempty = 0
                for index in range { if try !self.metadata(syntax.child(at: index)).isEmpty { nonempty += 1 } }
                count = nonempty
            default: count = try operandCount(kind)
            }
            if frame.finish {
                guard values.count >= count else { throw .invalidModel("Constant value stack underflow") }
                let start = values.count - count
                let result = try combine(frame, kind: kind, info: metadata, start: start, context: &context)
                let resized = try result.resizedBinary(to: LogicBitWidth(frame.width), signExtend: frame.signed, context: &context)
                values.removeSubrange(start..<values.count); values.append(resized)
                continue
            }
            let effective = try max(frame.width, metadata.type.width.value)
            guard frames.count + count + 1 <= info.count * 2 else { throw .invalidModel("Constant value frame capacity exhausted") }
            frames.append(Frame(node: frame.node, width: effective, signed: frame.signed, finish: true))
            let inputCount = if case .concatenate = kind { try operandCount(kind) } else { count }
            for index in (0..<inputCount).reversed() {
                let child: Int
                if case .repeated(_, let value) = kind { child = value }
                else { child = try operand(kind, at: index) }
                if try self.metadata(child).isEmpty { continue }
                let childType = try self.metadata(child).type
                var childWidth = childType.width.value; var childSign = childType.isSigned
                switch kind {
                case .unary(let operation, _):
                    if operation == .plus || operation == .minus || operation == .invert {
                        childWidth = effective; childSign = frame.signed
                    }
                case .binary(let operation, let lhs, let rhs):
                    switch operation {
                    case .logicalAnd, .logicalOr: break
                    case .equal, .notEqual, .caseEqual, .caseNotEqual, .less, .lessEqual, .greater, .greaterEqual:
                        let left = try self.metadata(lhs).type; let right = try self.metadata(rhs).type
                        childWidth = max(left.width.value, right.width.value); childSign = left.isSigned && right.isSigned
                    case .shiftLeft, .arithmeticLeft, .shiftRight, .arithmeticRight:
                        if index == 0 { childWidth = effective; childSign = frame.signed }
                    default: childWidth = effective; childSign = frame.signed
                    }
                case .conditional:
                    if index != 0 { childWidth = effective; childSign = frame.signed }
                default: break
                }
                frames.append(Frame(node: child, width: childWidth, signed: childSign, finish: false))
            }
        }
        guard values.count == 1, let result = values.popLast() else { throw .invalidModel("Constant evaluation did not produce one value") }
        return result
    }

    private borrowing func truth(_ value: borrowing LogicFourStateVector, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Bool { try value.reducingBinary(.or, context: &context) }
    private borrowing func boolean(_ value: Bool, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicFourStateVector {
        try LogicFourStateVector(repeating: value ? .one : .zero, width: LogicBitWidth(1), context: &context)
    }
    private borrowing func combine(_ frame: Frame, kind: SystemVerilogSyntaxNode.Kind, info: Info, start: Int,
        context: inout LogicKernelContext) throws(LogicKernelError) -> LogicFourStateVector {
        if let literal = info.literal { return try literal.resizedBinary(to: LogicBitWidth(frame.width), signExtend: frame.signed, context: &context) }
        if let fill = info.fill {
            return try LogicFourStateVector(repeating: fill ? .one : .zero, width: LogicBitWidth(frame.width), context: &context)
        }
        switch kind {
        case .signedCast: return values[start]
        case .unary(let operation, _):
            let value = values[start]
            switch operation {
            case .plus: return value
            case .minus: return try value.negatingBinary(context: &context)
            case .invert: return try value.invertingBinary(context: &context)
            case .logicalNot: return try boolean(!truth(value, context: &context), context: &context)
            case .reduceAnd, .reduceNand:
                let result = try value.reducingBinary(.and, context: &context)
                return try boolean(operation == .reduceAnd ? result : !result, context: &context)
            case .reduceOr, .reduceNor:
                let result = try truth(value, context: &context)
                return try boolean(operation == .reduceOr ? result : !result, context: &context)
            case .reduceXor, .reduceXnor:
                let result = try value.reducingBinary(.xor, context: &context)
                return try boolean(operation == .reduceXor ? result : !result, context: &context)
            }
        case .binary(let operation, let leftNode, let rightNode):
            let left = values[start]; let right = values[start + 1]
            switch operation {
            case .add: return try left.addingBinary(right, context: &context)
            case .subtract: return try left.subtractingBinary(right, context: &context)
            case .multiply: return try left.multiplyingBinary(right, context: &context)
            case .and: return try left.applyingBinary(.and, to: right, context: &context)
            case .or: return try left.applyingBinary(.or, to: right, context: &context)
            case .xor, .xnor:
                let xor = try left.applyingBinary(.xor, to: right, context: &context)
                return operation == .xor ? xor : try xor.invertingBinary(context: &context)
            case .shiftLeft, .arithmeticLeft: return try left.shiftingBinary(left: true, amount: right, context: &context)
            case .shiftRight, .arithmeticRight:
                return try left.shiftingBinary(left: false, amount: right,
                    arithmetic: operation == .arithmeticRight && frame.signed, context: &context)
            case .equal, .caseEqual, .notEqual, .caseNotEqual:
                let equal = try left.equalsBinary(right, context: &context)
                return try boolean(operation == .equal || operation == .caseEqual ? equal : !equal, context: &context)
            case .less, .lessEqual, .greater, .greaterEqual:
                let leftSigned = try metadata(leftNode).type.isSigned
                let rightSigned = try metadata(rightNode).type.isSigned
                let signed = leftSigned && rightSigned
                let result: Bool
                if operation == .less || operation == .greaterEqual { result = try left.isLessThanBinary(right, signed: signed, context: &context) }
                else { result = try right.isLessThanBinary(left, signed: signed, context: &context) }
                return try boolean(operation == .less || operation == .greater ? result : !result, context: &context)
            case .logicalAnd, .logicalOr:
                let lhs = try truth(left, context: &context); let rhs = try truth(right, context: &context)
                return try boolean(operation == .logicalAnd ? lhs && rhs : lhs || rhs, context: &context)
            }
        case .conditional:
            return try truth(values[start], context: &context) ? values[start + 1] : values[start + 2]
        case .select:
            return try values[start].slicingBinary(offset: info.offset, width: info.type.width, context: &context)
        case .concatenate, .repeated:
            return try assemble(info: info, start: start, context: &context)
        default: throw .invalidModel("Constant expression has no value implementation")
        }
    }
    private borrowing func assemble(info: Info, start: Int,
        context: inout LogicKernelContext) throws(LogicKernelError) -> LogicFourStateVector {
        let width = try info.type.width
        _ = try context.reserveStorage(byteCount: UInt64(width.wordCount) * 16)
        var words = [UInt64](repeating: 0, count: width.wordCount)
        var destination = 0
        let count = info.repetitions > 0 ? info.repetitions : values.count - start
        for index in (0..<count).reversed() {
            let value = values[info.repetitions > 0 ? start : start + index]
            for bit in 0..<value.width.value {
                try context.charge(.workUnits)
                if try value.bit(at: bit) == .one { words[destination / 64] |= UInt64(1) << (destination % 64) }
                destination += 1
            }
        }
        guard destination == width.value else { throw .invalidModel("Constant concatenation width differs from its type") }
        return try LogicFourStateVector(width: width, valueWords: words, unknownWords: [UInt64](repeating: 0, count: width.wordCount))
    }
}
