import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogExpressionEmission {
    mutating func combine(_ node:Int,type:WordLogicType,kind:SystemVerilogSyntaxNode.Kind,
        metadata:SystemVerilogConstantEvaluator.Info,start:Int,evaluator:inout SystemVerilogConstantEvaluator,
        builder:inout ElaboratedRTLBuilder,nextEntityID:inout UInt64,context:inout LogicKernelContext)
        throws(LogicKernelError)->SystemVerilogResolvedExpression {
        let result:SystemVerilogResolvedExpression
        switch kind {
        case .identifier:
            guard let signal = metadata.signal else {throw .invalidModel("Runtime expression name has no signal")}
            result = try emit(.read(signal),type:WordLogicType(width:metadata.type.width,isSigned:metadata.type.isSigned),node:node,
                inputs:[],evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
        case .signedCast(let signed,_):
            let input = values[start]
            result = try compute(.bitcast,type:WordLogicType(width:input.type.width,isSigned:signed),node:node,a:input,
                evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
        case .unary(let operation,_):
            result = try unary(operation,node:node,type:type,input:values[start],evaluator:evaluator,
                builder:&builder,nextEntityID:&nextEntityID,context:&context)
        case .binary(let operation,_,_):
            result = try binary(operation,node:node,type:type,left:values[start],right:values[start+1],
                evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
        case .conditional:
            let condition = try truth(values[start],node:node,evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
            result = try compute(.select,type:type,node:node,a:condition,b:values[start+1],c:values[start+2],
                evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
        case .select:
            let selectedType = WordLogicType(width:try metadata.type.width)
            if let dynamic = metadata.dynamicSelection {
                let offset = try normalizedOffset(values[start+1],selection:dynamic,node:node,evaluator:evaluator,
                    builder:&builder,nextEntityID:&nextEntityID,context:&context)
                inputs.removeAll(keepingCapacity:true);inputs.append(values[start].index);inputs.append(offset.index)
                let supplied = inputs
                result = try emit(.dynamicSelect,type:selectedType,node:node,inputs:supplied,evaluator:evaluator,
                    builder:&builder,nextEntityID:&nextEntityID,context:&context)
            } else {
                result = try compute(.slice(offset:metadata.offset),type:selectedType,node:node,a:values[start],
                    evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
            }
        case .concatenate:
            inputs.removeAll(keepingCapacity:true)
            for index in start..<values.count {try context.charge(.workUnits);inputs.append(values[index].index)}
            let supplied = inputs
            result = try emit(.compute(.concatenate),type:WordLogicType(width:metadata.type.width),node:node,inputs:supplied,
                evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
        case .repeated:
            let count = metadata.repetitions
            guard count > 0 else {throw .invalidModel("An empty repetition cannot be emitted alone")}
            let scratch = try context.reserveStorage(byteCount:try SystemVerilogConstantEvaluator.bytes(count,MemoryLayout<RTLExpressionIndex>.stride))
            do throws(LogicKernelError) {
                try context.charge(.workUnits,amount:UInt64(count))
                let repeated = [RTLExpressionIndex](repeating:values[start].index,count:count)
                result = try emit(.compute(.concatenate),type:WordLogicType(width:metadata.type.width),node:node,inputs:repeated,
                    evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
            } catch {try context.releaseStorage(scratch);throw error}
            try context.releaseStorage(scratch)
        default:throw try evaluator.failure(node,"SV_EXPRESSION_OPERATION","Expression has no admitted RTL operation")
        }
        return try convert(result,to:type,signExtend:type.isSigned,node:node,evaluator:evaluator,
            builder:&builder,nextEntityID:&nextEntityID,context:&context)
    }
    mutating func truth(_ input:SystemVerilogResolvedExpression,node:Int,evaluator:borrowing SystemVerilogConstantEvaluator,
        builder:inout ElaboratedRTLBuilder,nextEntityID:inout UInt64,context:inout LogicKernelContext)
        throws(LogicKernelError)->SystemVerilogResolvedExpression {
        let boolean = WordLogicType(width:try LogicBitWidth(1))
        if input.type == boolean {return input}
        return try compute(.reduceOr,type:boolean,node:node,a:input,evaluator:evaluator,
            builder:&builder,nextEntityID:&nextEntityID,context:&context)
    }
    mutating func unary(_ operation:SystemVerilogSyntaxNode.Unary,node:Int,type:WordLogicType,
        input:SystemVerilogResolvedExpression,evaluator:borrowing SystemVerilogConstantEvaluator,
        builder:inout ElaboratedRTLBuilder,nextEntityID:inout UInt64,context:inout LogicKernelContext)
        throws(LogicKernelError)->SystemVerilogResolvedExpression {
        if operation == .plus {return input}
        let opcode:WordLogicOpcode;let inverted:Bool;let resultType:WordLogicType
        switch operation {
        case .plus:throw .invalidModel("Unary plus reached opcode selection")
        case .minus:opcode = .negate;inverted = false;resultType = type
        case .invert:opcode = .invert;inverted = false;resultType = type
        case .logicalNot:opcode = .logicalNot;inverted = false;resultType = WordLogicType(width:try LogicBitWidth(1))
        case .reduceAnd,.reduceNand:opcode = .reduceAnd;inverted = operation == .reduceNand;resultType = WordLogicType(width:try LogicBitWidth(1))
        case .reduceOr,.reduceNor:opcode = .reduceOr;inverted = operation == .reduceNor;resultType = WordLogicType(width:try LogicBitWidth(1))
        case .reduceXor,.reduceXnor:opcode = .reduceXor;inverted = operation == .reduceXnor;resultType = WordLogicType(width:try LogicBitWidth(1))
        }
        let value = try compute(opcode,type:resultType,node:node,a:input,evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
        if !inverted {return value}
        return try compute(.logicalNot,type:resultType,node:node,a:value,evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
    }
    mutating func binary(_ operation:SystemVerilogSyntaxNode.Binary,node:Int,type:WordLogicType,
        left:SystemVerilogResolvedExpression,right:SystemVerilogResolvedExpression,evaluator:borrowing SystemVerilogConstantEvaluator,
        builder:inout ElaboratedRTLBuilder,nextEntityID:inout UInt64,context:inout LogicKernelContext)
        throws(LogicKernelError)->SystemVerilogResolvedExpression {
        let boolean = WordLogicType(width:try LogicBitWidth(1))
        var a = left;var b = right
        let opcode:WordLogicOpcode;let resultType:WordLogicType;let inverted:Bool
        switch operation {
        case .add:opcode = .add;resultType = type;inverted = false
        case .subtract:opcode = .subtract;resultType = type;inverted = false
        case .multiply:opcode = .multiply;resultType = type;inverted = false
        case .and:opcode = .and;resultType = type;inverted = false
        case .or:opcode = .or;resultType = type;inverted = false
        case .xor,.xnor:opcode = .xor;resultType = type;inverted = operation == .xnor
        case .logicalAnd:opcode = .logicalAnd;resultType = boolean;inverted = false
        case .logicalOr:opcode = .logicalOr;resultType = boolean;inverted = false
        case .equal,.notEqual:opcode = .equal;resultType = boolean;inverted = operation == .notEqual
        case .caseEqual,.caseNotEqual:
            inputs.removeAll(keepingCapacity:true);inputs.append(a.index);inputs.append(b.index)
            let supplied = inputs
            let value = try emit(.caseEqual,type:boolean,node:node,inputs:supplied,evaluator:evaluator,
                builder:&builder,nextEntityID:&nextEntityID,context:&context)
            if operation == .caseEqual {return value}
            return try compute(.logicalNot,type:boolean,node:node,a:value,evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
        case .less,.lessEqual,.greater,.greaterEqual:
            opcode = .lessThan;resultType = boolean;inverted = operation == .lessEqual || operation == .greaterEqual
            if operation == .greater || operation == .lessEqual {a = right;b = left}
        case .shiftLeft,.arithmeticLeft,.shiftRight,.arithmeticRight:
            opcode = operation == .shiftLeft || operation == .arithmeticLeft ? .shiftLeft : .shiftRight(arithmetic:operation == .arithmeticRight && type.isSigned)
            resultType = type;inverted = false
            b = try convert(b,to:WordLogicType(width:b.type.width),signExtend:false,node:node,evaluator:evaluator,
                builder:&builder,nextEntityID:&nextEntityID,context:&context)
        }
        let result = try compute(opcode,type:resultType,node:node,a:a,b:b,evaluator:evaluator,
            builder:&builder,nextEntityID:&nextEntityID,context:&context)
        if !inverted {return result}
        return try compute(opcode == .xor ? .invert : .logicalNot,type:resultType,node:node,a:result,
            evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
    }
}
