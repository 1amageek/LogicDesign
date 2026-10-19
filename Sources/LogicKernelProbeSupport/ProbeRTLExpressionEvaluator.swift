import LogicIR
import LogicKernelCore

// Verification-only interpreter for binary RTL expressions. Unknown output bits
// are modeled for dynamic selection; this is not the production event simulator.
@available(macOS 26.0, *)
package struct ProbeRTLExpressionEvaluator {
    package static func evaluate(_ model:borrowing ElaboratedRTL,signals:borrowing [LogicFourStateVector],
        result:RTLExpressionIndex,context:inout LogicKernelContext)throws(LogicKernelError)->LogicFourStateVector {
        let scratch = try context.reserveStorage(byteCount:UInt64(model.expressionCount) * UInt64(MemoryLayout<LogicFourStateVector?>.stride))
        let output:LogicFourStateVector
        do throws(LogicKernelError) {
            output = try model.withExpressions { (expressions,operands,order) throws(LogicKernelError) in
                var values = [LogicFourStateVector?](repeating:nil,count:expressions.count)
                for ordinal in 0..<order.count {
                    let index = order[ordinal]
                    try context.charge(.workUnits)
                    let expression = expressions[index.rawValue]
                    var args:[LogicFourStateVector] = []
                    for offset in expression.operands {
                        guard let value = values[operands[offset].rawValue] else {throw .invalidModel("Probe operand is unavailable")}
                        args.append(value)
                    }
                    let value:LogicFourStateVector
                    switch expression.operation {
                    case .read(let signal):
                        guard signals.indices.contains(signal.rawValue) else {throw .invalidInput("Probe signal is absent")}
                        value = signals[signal.rawValue]
                    case .constant(let constant):value = constant
                    case .compute(let operation):
                        value = try compute(operation,type:expression.type,args:args,operandSigned:expression.operands.isEmpty ? false : expressions[operands[expression.operands.lowerBound].rawValue].type.isSigned,context:&context)
                    case .caseEqual:value = try boolean(args[0] == args[1],context:&context)
                    case .dynamicSelect:
                        let offsetType = expressions[operands[expression.operands.lowerBound+1].rawValue].type
                        value = try select(args[0],offset:args[1],signed:offsetType.isSigned,width:expression.type.width,context:&context)
                    }
                    values[index.rawValue] = value
                }
                guard values.indices.contains(result.rawValue),let value = values[result.rawValue] else {throw .invalidInput("Probe result is unavailable")}
                return value
            }
        } catch {try context.releaseStorage(scratch);throw error}
        try context.releaseStorage(scratch)
        return output
    }
    private static func boolean(_ value:Bool,context:inout LogicKernelContext)throws(LogicKernelError)->LogicFourStateVector {
        try LogicFourStateVector(repeating:value ? .one : .zero,width:LogicBitWidth(1),context:&context)
    }
    private static func compute(_ operation:WordLogicOpcode,type:WordLogicType,args:borrowing [LogicFourStateVector],
        operandSigned:Bool,context:inout LogicKernelContext)throws(LogicKernelError)->LogicFourStateVector {
        switch operation {
        case .bitcast:return args[0]
        case .zeroExtend:return try args[0].resizedBinary(to:type.width,signExtend:false,context:&context)
        case .signExtend:return try args[0].resizedBinary(to:type.width,signExtend:true,context:&context)
        case .slice(let offset):return try args[0].slicingBinary(offset:offset,width:type.width,context:&context)
        case .invert:return try args[0].invertingBinary(context:&context)
        case .negate:return try args[0].negatingBinary(context:&context)
        case .and:return try args[0].applyingBinary(.and,to:args[1],context:&context)
        case .or:return try args[0].applyingBinary(.or,to:args[1],context:&context)
        case .xor:return try args[0].applyingBinary(.xor,to:args[1],context:&context)
        case .add:return try args[0].addingBinary(args[1],context:&context)
        case .subtract:return try args[0].subtractingBinary(args[1],context:&context)
        case .multiply:return try args[0].multiplyingBinary(args[1],context:&context)
        case .equal:return try boolean(args[0].equalsBinary(args[1],context:&context),context:&context)
        case .lessThan:return try boolean(args[0].isLessThanBinary(args[1],signed:operandSigned,context:&context),context:&context)
        case .logicalNot:return try boolean(!args[0].reducingBinary(.or,context:&context),context:&context)
        case .logicalAnd,.logicalOr:
            let a = try args[0].reducingBinary(.or,context:&context);let b = try args[1].reducingBinary(.or,context:&context)
            return try boolean(operation == .logicalAnd ? a && b : a || b,context:&context)
        case .reduceAnd:return try boolean(args[0].reducingBinary(.and,context:&context),context:&context)
        case .reduceOr:return try boolean(args[0].reducingBinary(.or,context:&context),context:&context)
        case .reduceXor:return try boolean(args[0].reducingBinary(.xor,context:&context),context:&context)
        case .shiftLeft:return try args[0].shiftingBinary(left:true,amount:args[1],context:&context)
        case .shiftRight(let arithmetic):return try args[0].shiftingBinary(left:false,amount:args[1],arithmetic:arithmetic,context:&context)
        case .select:return try args[0].reducingBinary(.or,context:&context) ? args[1] : args[2]
        case .concatenate:
            guard let first = args.first else {throw .invalidModel("Empty probe concatenation")}
            var value = first
            for index in 1..<args.count {value = try value.concatenatingBinary(args[index],context:&context)}
            return value
        }
    }
    private static func select(_ vector:borrowing LogicFourStateVector,offset:borrowing LogicFourStateVector,
        signed:Bool,width:LogicBitWidth,context:inout LogicKernelContext)throws(LogicKernelError)->LogicFourStateVector {
        let base:Int
        do throws(LogicKernelError) {base = try offset.binaryInt(signed:signed,context:&context)}
        catch {
            guard case .invalidModel = error else {throw error}
            return try LogicFourStateVector(repeating:.unknown,width:width,context:&context)
        }
        _ = try context.reserveStorage(byteCount:UInt64(width.wordCount) * 16)
        var words = [UInt64](repeating:0,count:width.wordCount)
        var unknown = words
        for bit in 0..<width.value {
            try context.charge(.workUnits)
            let selected = base.addingReportingOverflow(bit)
            if selected.overflow || selected.partialValue < 0 || selected.partialValue >= vector.width.value {
                unknown[bit/64] |= 1 << (bit%64)
            } else {
                let value = try vector.bit(at:selected.partialValue)
                guard value.isKnown else {throw .invalidInput("Probe reference only admits binary vector inputs")}
                if value == .one {words[bit/64] |= 1 << (bit%64)}
            }
        }
        return try LogicFourStateVector(width:width,valueWords:words,unknownWords:unknown)
    }
}
