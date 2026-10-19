import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogConstantEvaluator {
    internal mutating func infer(_ root: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        pending.append(root)
        while let entry = pending.popLast() {
            try context.charge(.workUnits)
            let node = entry < 0 ? ~entry : entry
            guard info.indices.contains(node) else { throw .invalidModel("Constant node outside syntax") }
            if info[node] != nil { continue }
            if entry < 0 {
                var completed = try inferCompleted(node, context: &context)
                completed.containsRuntime = completed.signal != nil
                let kind = try syntax.node(at:node).kind
                for index in 0..<(try operandCount(kind)) {
                    if try metadata(operand(kind,at:index)).containsRuntime {completed.containsRuntime = true}
                }
                info[node] = completed; continue
            }
            guard pending.count < info.count * 2 else { throw .invalidModel("Constant type stack capacity exhausted") }
            pending.append(~node)
            let kind = try syntax.node(at: node).kind
            let count = try operandCount(kind)
            for offset in (0..<count).reversed() {
                let child = try operand(kind, at: offset)
                guard child >= 0 && child < node else { throw .invalidModel("Constant syntax must point to earlier nodes") }
                pending.append(child)
            }
        }
    }
    internal borrowing func operandCount(_ kind: SystemVerilogSyntaxNode.Kind) throws(LogicKernelError) -> Int {
        switch kind {
        case .identifier, .literal: return 0
        case .unary, .signedCast: return 1
        case .binary, .repeated: return 2
        case .conditional: return 3
        case .select(_, _, _, let second): return second == nil ? 2 : 3
        case .concatenate(let range): return range.count
        default: throw .invalidModel("Expected a constant expression")
        }
    }
    internal borrowing func operand(_ kind: SystemVerilogSyntaxNode.Kind, at index: Int) throws(LogicKernelError) -> Int {
        switch kind {
        case .unary(_, let value), .signedCast(_, let value): return value
        case .binary(_, let left, let right), .repeated(let left, let right): return index == 0 ? left : right
        case .conditional(let condition, let then, let otherwise): return index == 0 ? condition : index == 1 ? then : otherwise
        case .select(_, let value, let first, let second):
            if index == 0 { return value }; if index == 1 { return first }
            guard let second else { throw .invalidModel("Missing selection operand") }; return second
        case .concatenate(let range): return try syntax.child(at: range.lowerBound + index)
        default: throw .invalidModel("Constant expression has no operand")
        }
    }
    private mutating func inferCompleted(_ node: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Info {
        let syntaxNode = try syntax.node(at: node)
        let count = try operandCount(syntaxNode.kind)
        for offset in 0..<count {
            let child = try operand(syntaxNode.kind, at: offset)
            if try metadata(child).isEmpty {
                switch syntaxNode.kind {
                case .concatenate: break
                case .repeated where offset == 1: break
                default: throw try failure(child, "SV_CONSTANT_EMPTY", "Empty repetition is only valid as a concatenation operand")
                }
            }
        }
        switch syntaxNode.kind {
        case .literal:
            let literal = try SystemVerilogSynthesisIntegerDecoder().decode(syntaxNode.byteRange, in: syntax.source, context: &context)
            switch literal {
            case .fill(let bit): return Info(type: try SystemVerilogConstantType(width: 1, indefinite: true), fill: bit)
            case .integer(let value, let signed, let unsized):
                return Info(type: try SystemVerilogConstantType(width: value.width.value, signed: signed, indefinite: unsized), literal: value)
            }
        case .identifier(let name):
            if let signalScope {
                let resolved = try signalScope.resolve(name,reference:node,context:&context)
                var result = Info(type:resolved.type,literal:resolved.value)
                result.signal = resolved.signal
                return result
            }
            let constant = try resolveConstant(name, reference: node, context: &context)
            return Info(type: constant.type, literal: constant.value)
        case .signedCast(let signed, let value):
            let input = try metadata(value).type
            return Info(type: try SystemVerilogConstantType(width: input.width.value, signed: signed))
        case .unary(let operation, let value):
            let type = try metadata(value).type
            switch operation {
            case .plus, .minus, .invert: return Info(type: try SystemVerilogConstantType(width: type.width.value,
                signed: type.isSigned))
            default: return Info(type: try SystemVerilogConstantType(width: 1))
            }
        case .binary(let operation, let left, let right):
            let lhs = try metadata(left).type; let rhs = try metadata(right).type
            switch operation {
            case .less, .lessEqual, .greater, .greaterEqual, .equal, .notEqual, .caseEqual, .caseNotEqual, .logicalAnd, .logicalOr:
                return Info(type: try SystemVerilogConstantType(width: 1))
            case .shiftLeft, .shiftRight, .arithmeticLeft, .arithmeticRight:
                return Info(type: try SystemVerilogConstantType(width: lhs.width.value,
                    signed: lhs.isSigned))
            default:
                return Info(type: try SystemVerilogConstantType(width: max(lhs.width.value, rhs.width.value),
                    signed: lhs.isSigned && rhs.isSigned))
            }
        case .conditional(_, let then, let otherwise):
            let lhs = try metadata(then).type; let rhs = try metadata(otherwise).type
            return Info(type: try SystemVerilogConstantType(width: max(lhs.width.value, rhs.width.value),
                signed: lhs.isSigned && rhs.isSigned))
        case .concatenate(let range):
            var width = 0
            for offset in range {
                try context.charge(.workUnits)
                let child = try syntax.child(at: offset); let input = try metadata(child)
                if input.isEmpty { continue }
                let type = try input.type
                guard !type.isIndefinite || input.fill != nil else {
                    throw try failure(child, "SV_CONSTANT_CONCAT_SIZE", "Concatenation operand has indefinite width")
                }
                let sum = width.addingReportingOverflow(type.width.value)
                guard !sum.overflow else { throw try failure(node, "SV_CONSTANT_WIDTH", "Concatenation width overflow") }
                width = sum.partialValue
            }
            guard width > 0 else { throw try failure(node, "SV_CONSTANT_EMPTY", "Concatenation must contain at least one bit") }
            try context.observeBitWidth(UInt64(width))
            return Info(type: try SystemVerilogConstantType(width: width))
        case .repeated(let countNode, let value):
            try requireConstantSyntax(countNode, context: &context)
            let count = try integer(countNode, context: &context); let input = try metadata(value)
            guard count >= 0 else { throw try failure(countNode, "SV_CONSTANT_REPEAT_COUNT", "Repetition count must not be negative") }
            if input.isEmpty { return Info() }
            let type = try input.type
            guard !type.isIndefinite || input.fill != nil else {
                throw try failure(value, "SV_CONSTANT_CONCAT_SIZE", "Repetition operand has indefinite width")
            }
            if count == 0 { return Info() }
            let product = type.width.value.multipliedReportingOverflow(by: count)
            guard !product.overflow else { throw try failure(node, "SV_CONSTANT_WIDTH", "Repetition width overflow") }
            try context.observeBitWidth(UInt64(product.partialValue))
            return Info(type: try SystemVerilogConstantType(width: product.partialValue), repetitions: count)
        case .select(let selection, let value, let first, let second):
            return try selectionInfo(node, selection, value, first, second, context: &context)
        default: throw try failure(node, "SV_CONSTANT_EXPRESSION", "Unsupported constant expression syntax")
        }
    }
    private mutating func selectionInfo(_ node: Int, _ selection: SystemVerilogSyntaxNode.Selection,
        _ value: Int, _ first: Int, _ second: Int?, context: inout LogicKernelContext) throws(LogicKernelError) -> Info {
        let type = try metadata(value).type
        let dimension: SystemVerilogPackedDimension
        if let first = type.dimensions.first { dimension = first }
        else { dimension = try SystemVerilogPackedDimension(left: type.width.value - 1, right: 0) }
        let unit = type.width.value / dimension.count
        if selection == .range { try requireConstantSyntax(first, context: &context) }
        if let second { try requireConstantSyntax(second, context: &context) }
        let writable = !writableSelections.isEmpty && writableSelections[node]
        if try metadata(first).containsRuntime || (writable && selection != .range) {
            guard selection != .range else {
                throw try failure(first,"SV_SELECT_CONSTANT_RANGE","Fixed part-select bounds must be constant")
            }
            let count: Int
            if selection == .bit {count = 1}
            else {
                guard let second else {throw .invalidModel("Missing indexed selection width")}
                count = try integer(second,context:&context)
                guard count > 0 else {throw try failure(second,"SV_CONSTANT_SELECT_WIDTH","Indexed part-select width must be positive")}
            }
            let width = count.multipliedReportingOverflow(by:unit)
            guard !width.overflow else {throw try failure(node,"SV_CONSTANT_WIDTH","Selection width overflow")}
            try context.observeBitWidth(UInt64(width.partialValue))
            let dimensions = try selectedDimensions(type,selection:selection,count:count,context:&context)
            var result = Info(type:try SystemVerilogConstantType(width:width.partialValue,dimensions:dimensions))
            result.dynamicSelection = SystemVerilogDynamicSelection(rightBound:dimension.right,
                descending:dimension.left >= dimension.right,
                adjustment:selection == .indexedUp && dimension.left < dimension.right ? count-1 : selection == .indexedDown && dimension.left >= dimension.right ? -(count-1) : 0,
                unit:unit)
            return result
        }
        let index = try integer(first, context: &context)
        let left: Int; let right: Int
        if selection == .bit { left = index; right = index }
        else {
            guard let second else { throw .invalidModel("Missing part-select bound") }
            let bound = try integer(second, context: &context)
            if selection == .range { left = index; right = bound }
            else {
                guard bound > 0 else { throw try failure(second, "SV_CONSTANT_SELECT_WIDTH", "Indexed part-select width must be positive") }
                let endpoint = selection == .indexedUp ? index.addingReportingOverflow(bound - 1) : index.subtractingReportingOverflow(bound - 1)
                guard !endpoint.overflow else { throw try failure(node, "SV_CONSTANT_INDEX", "Indexed part-select bound overflow") }
                let low = min(index, endpoint.partialValue); let high = max(index, endpoint.partialValue)
                left = dimension.left >= dimension.right ? high : low
                right = dimension.left >= dimension.right ? low : high
            }
            guard (dimension.left >= dimension.right && left >= right) || (dimension.left <= dimension.right && left <= right) else {
                throw try failure(node, "SV_CONSTANT_SELECT_DIRECTION", "Part-select direction differs from the declared range")
            }
        }
        let firstOffset: Int; let lastOffset: Int
        do throws(LogicKernelError) {
            if writable {
                let a = dimension.left >= dimension.right ? left.subtractingReportingOverflow(dimension.right) : dimension.right.subtractingReportingOverflow(left)
                let b = dimension.left >= dimension.right ? right.subtractingReportingOverflow(dimension.right) : dimension.right.subtractingReportingOverflow(right)
                guard !a.overflow, !b.overflow else { throw .invalidInput("Writable selection offset overflow") }
                firstOffset = a.partialValue; lastOffset = b.partialValue
            } else {
                firstOffset = try dimension.offset(of: left); lastOffset = try dimension.offset(of: right)
            }
        } catch { throw try failure(node, "SV_SYNTHESIS_SELECT_X", "Constant selection would contain an out-of-range X") }
        let difference = max(firstOffset,lastOffset).subtractingReportingOverflow(min(firstOffset,lastOffset))
        guard !difference.overflow, difference.partialValue < Int.max else { throw try failure(node,"SV_CONSTANT_WIDTH","Selection width overflow") }
        let count = difference.partialValue + 1
        let width = count.multipliedReportingOverflow(by: unit)
        let offset = min(firstOffset,lastOffset).multipliedReportingOverflow(by: unit)
        guard !width.overflow, !offset.overflow else { throw try failure(node,"SV_CONSTANT_WIDTH","Selection width or offset overflow") }
        try context.observeBitWidth(UInt64(width.partialValue))
        let dimensions = try selectedDimensions(type,selection:selection,count:count,context:&context)
        return Info(type: try SystemVerilogConstantType(width: width.partialValue, dimensions: dimensions), offset: offset.partialValue)
    }
    private mutating func selectedDimensions(_ type: SystemVerilogConstantType,
        selection: SystemVerilogSyntaxNode.Selection, count: Int, context:inout LogicKernelContext)
        throws(LogicKernelError) -> [SystemVerilogPackedDimension] {
        var dimensions: [SystemVerilogPackedDimension] = []
        let dimensionCount = max(0,type.dimensions.count-1) + (selection == .bit ? 0 : 1)
        _ = try context.reserveStorage(byteCount:UInt64(dimensionCount) * UInt64(MemoryLayout<SystemVerilogPackedDimension>.stride))
        dimensions.reserveCapacity(dimensionCount)
        if selection != .bit {dimensions.append(try SystemVerilogPackedDimension(left:count-1,right:0))}
        for offset in 1..<max(1,type.dimensions.count) {dimensions.append(type.dimensions[offset])}
        return dimensions
    }

}
