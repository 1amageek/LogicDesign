import CircuiteFoundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
internal struct SystemVerilogExpressionEmission: ~Copyable {
    struct Frame {let node:Int;let type:WordLogicType;let finish:Bool}
    var frames:[Frame] = []
    var values:[SystemVerilogResolvedExpression] = []
    var inputs:[RTLExpressionIndex] = []

    mutating func compile(_ node:Int,type:WordLogicType,evaluator:inout SystemVerilogConstantEvaluator,
        builder:inout ElaboratedRTLBuilder,nextEntityID:inout UInt64,context:inout LogicKernelContext)
        throws(LogicKernelError) -> SystemVerilogResolvedExpression {
        frames.append(Frame(node:node,type:type,finish:false))
        while let frame = frames.popLast() {
            try context.charge(.workUnits)
            let metadata = try evaluator.metadata(frame.node)
            let effective = WordLogicType(width:try LogicBitWidth(max(frame.type.width.value,metadata.type.width.value)),isSigned:frame.type.isSigned)
            if !metadata.containsRuntime {
                let value = try evaluator.evaluateExpression(frame.node,width:effective.width.value,signed:effective.isSigned,context:&context)
                values.append(try emit(.constant(value),type:effective,node:frame.node,inputs:[],evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context))
                continue
            }
            let kind = try evaluator.syntax.node(at:frame.node).kind
            let count = try emittedCount(kind,metadata:metadata,evaluator:evaluator,context:&context)
            if frame.finish {
                guard values.count >= count else {throw .invalidModel("Expression emission stack underflow")}
                let start = values.count-count
                let value = try combine(frame.node,type:effective,kind:kind,metadata:metadata,start:start,
                    evaluator:&evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
                values.removeSubrange(start..<values.count);values.append(value)
            } else {
                guard frames.count+count+1 <= evaluator.info.count*2 else {throw .invalidModel("Expression emission capacity exhausted")}
                frames.append(Frame(node:frame.node,type:effective,finish:true))
                if case .concatenate(let children) = kind {
                    for offset in children.reversed() {
                        try context.charge(.workUnits)
                        let child = try evaluator.syntax.child(at:offset)
                        if try evaluator.metadata(child).isEmpty {continue}
                        let own = try evaluator.metadata(child).type
                        frames.append(Frame(node:child,type:WordLogicType(width:own.width,isSigned:own.isSigned),finish:false))
                    }
                } else {
                    for index in (0..<count).reversed() {
                        let child = try emittedOperand(kind,index:index,metadata:metadata,evaluator:evaluator)
                        let childType = try contextualType(kind,index:index,result:effective,child:child,evaluator:evaluator)
                        frames.append(Frame(node:child,type:childType,finish:false))
                    }
                }
            }
        }
        guard values.count == 1,let result = values.popLast() else {throw .invalidModel("Expression emission did not produce one value")}
        return try convert(result,to:type,signExtend:type.isSigned,node:node,evaluator:evaluator,
            builder:&builder,nextEntityID:&nextEntityID,context:&context)
    }
    borrowing func emittedCount(_ kind:SystemVerilogSyntaxNode.Kind,metadata:SystemVerilogConstantEvaluator.Info,
        evaluator:borrowing SystemVerilogConstantEvaluator,context:inout LogicKernelContext) throws(LogicKernelError)->Int {
        switch kind {
        case .select:return metadata.dynamicSelection == nil ? 1 : 2
        case .repeated:return 1
        case .concatenate(let children):
            var count = 0
            for offset in children {try context.charge(.workUnits);if try !evaluator.metadata(evaluator.syntax.child(at:offset)).isEmpty {count += 1}}
            return count
        default:return try evaluator.operandCount(kind)
        }
    }
    borrowing func emittedOperand(_ kind:SystemVerilogSyntaxNode.Kind,index:Int,metadata:SystemVerilogConstantEvaluator.Info,
        evaluator:borrowing SystemVerilogConstantEvaluator) throws(LogicKernelError)->Int {
        switch kind {
        case .repeated(_,let value):return value
        default:return try evaluator.operand(kind,at:index)
        }
    }
    borrowing func contextualType(_ kind:SystemVerilogSyntaxNode.Kind,index:Int,result:WordLogicType,child:Int,
        evaluator:borrowing SystemVerilogConstantEvaluator)throws(LogicKernelError)->WordLogicType {
        let own = try evaluator.metadata(child).type
        switch kind {
        case .unary(let operation,_):
            if operation == .plus || operation == .minus || operation == .invert {return result}
        case .binary(let operation,let left,let right):
            switch operation {
            case .logicalAnd,.logicalOr:break
            case .equal,.notEqual,.caseEqual,.caseNotEqual,.less,.lessEqual,.greater,.greaterEqual:
                let lhs = try evaluator.metadata(left).type;let rhs = try evaluator.metadata(right).type
                return WordLogicType(width:try LogicBitWidth(max(lhs.width.value,rhs.width.value)),isSigned:lhs.isSigned && rhs.isSigned)
            case .shiftLeft,.arithmeticLeft,.shiftRight,.arithmeticRight:if index == 0 {return result}
            default:return result
            }
        case .conditional:if index != 0 {return result}
        default:break
        }
        return WordLogicType(width:own.width,isSigned:own.isSigned)
    }
    mutating func emit(_ operation:RTLResolvedExpression.Operation,type:WordLogicType,node:Int,
        inputs:borrowing [RTLExpressionIndex],evaluator:borrowing SystemVerilogConstantEvaluator,
        builder:inout ElaboratedRTLBuilder,nextEntityID:inout UInt64,context:inout LogicKernelContext)
        throws(LogicKernelError)->SystemVerilogResolvedExpression {
        guard nextEntityID > 0,nextEntityID < UInt64.max else {throw .invalidInput("Expression entity-ID namespace exhausted")}
        let id:DesignEntityID
        do {id = try DesignEntityID(rawValue:nextEntityID)}
        catch {throw .invalidModel("Foundation rejected an admitted entity identifier")}
        let range = try evaluator.syntax.node(at:node).byteRange
        let origin = try evaluator.syntax.source.origin(for: range)
        let index = try builder.addExpression(id:id,type:type,operation:operation,inputs:inputs,origin:origin,context:&context)
        nextEntityID += 1
        return SystemVerilogResolvedExpression(index:index,type:type)
    }
    mutating func compute(_ opcode:WordLogicOpcode,type:WordLogicType,node:Int,
        a:SystemVerilogResolvedExpression,b:SystemVerilogResolvedExpression? = nil,c:SystemVerilogResolvedExpression? = nil,
        evaluator:borrowing SystemVerilogConstantEvaluator,builder:inout ElaboratedRTLBuilder,
        nextEntityID:inout UInt64,context:inout LogicKernelContext)throws(LogicKernelError)->SystemVerilogResolvedExpression {
        inputs.removeAll(keepingCapacity:true);inputs.append(a.index)
        if let b {inputs.append(b.index)};if let c {inputs.append(c.index)}
        // The input buffer is borrowed; only final scalar operand references enter the builder.
        let supplied = inputs
        return try emit(.compute(opcode),type:type,node:node,inputs:supplied,evaluator:evaluator,
            builder:&builder,nextEntityID:&nextEntityID,context:&context)
    }
    mutating func convert(_ input:SystemVerilogResolvedExpression,to type:WordLogicType,signExtend:Bool,node:Int,
        evaluator:borrowing SystemVerilogConstantEvaluator,builder:inout ElaboratedRTLBuilder,
        nextEntityID:inout UInt64,context:inout LogicKernelContext)throws(LogicKernelError)->SystemVerilogResolvedExpression {
        var result = input
        if result.type.width.value > type.width.value {
            result = try compute(.slice(offset:0),type:WordLogicType(width:type.width),node:node,a:result,
                evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
        } else if result.type.width.value < type.width.value {
            if signExtend && !result.type.isSigned {
                result = try compute(.bitcast,type:WordLogicType(width:result.type.width,isSigned:true),node:node,a:result,
                    evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
            }
            result = try compute(signExtend ? .signExtend : .zeroExtend,type:type,node:node,a:result,
                evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
        }
        if result.type != type {
            result = try compute(.bitcast,type:type,node:node,a:result,evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
        }
        return result
    }
}
