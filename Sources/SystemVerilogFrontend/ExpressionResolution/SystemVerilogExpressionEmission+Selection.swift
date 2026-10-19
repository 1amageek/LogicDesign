import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogExpressionEmission {
    mutating func normalizedOffset(_ input:SystemVerilogResolvedExpression,selection:SystemVerilogDynamicSelection,
        node:Int,evaluator:borrowing SystemVerilogConstantEvaluator,builder:inout ElaboratedRTLBuilder,
        nextEntityID:inout UInt64,context:inout LogicKernelContext)throws(LogicKernelError)->SystemVerilogResolvedExpression {
        // Preserve zero-based descending bit indexes directly so range-proven unsigned
        // selectors retain their precise domain for synthesis admission.
        if selection.descending && selection.rightBound == 0 && selection.adjustment == 0 && selection.unit == 1 {return input}
        let type = try selection.offsetType(for: input.type)
        try context.observeBitWidth(UInt64(type.width.value))
        var offset = try convert(input,to:type,signExtend:input.type.isSigned,node:node,evaluator:evaluator,
            builder:&builder,nextEntityID:&nextEntityID,context:&context)
        if selection.adjustment != 0 {
            let adjustment = try integerConstant(selection.adjustment,type:type,node:node,evaluator:evaluator,
                builder:&builder,nextEntityID:&nextEntityID,context:&context)
            offset = try compute(.add,type:type,node:node,a:offset,b:adjustment,evaluator:evaluator,
                builder:&builder,nextEntityID:&nextEntityID,context:&context)
        }
        let bound = try integerConstant(selection.rightBound,type:type,node:node,evaluator:evaluator,
            builder:&builder,nextEntityID:&nextEntityID,context:&context)
        offset = try compute(.subtract,type:type,node:node,a:selection.descending ? offset : bound,
            b:selection.descending ? bound : offset,evaluator:evaluator,builder:&builder,nextEntityID:&nextEntityID,context:&context)
        if selection.unit != 1 {
            let unit = try integerConstant(selection.unit,type:type,node:node,evaluator:evaluator,
                builder:&builder,nextEntityID:&nextEntityID,context:&context)
            offset = try compute(.multiply,type:type,node:node,a:offset,b:unit,evaluator:evaluator,
                builder:&builder,nextEntityID:&nextEntityID,context:&context)
        }
        return offset
    }
    mutating func integerConstant(_ integer:Int,type:WordLogicType,node:Int,evaluator:borrowing SystemVerilogConstantEvaluator,
        builder:inout ElaboratedRTLBuilder,nextEntityID:inout UInt64,context:inout LogicKernelContext)
        throws(LogicKernelError)->SystemVerilogResolvedExpression {
        _ = try context.reserveStorage(byteCount:UInt64(type.width.wordCount) * 16)
        var words = [UInt64](repeating:integer < 0 ? .max : 0,count:type.width.wordCount)
        words[0] = UInt64(truncatingIfNeeded:integer)
        words[words.count-1] &= type.width.tailMask
        let value = try LogicFourStateVector(width:type.width,valueWords:words,
            unknownWords:[UInt64](repeating:0,count:type.width.wordCount))
        return try emit(.constant(value),type:type,node:node,inputs:[],evaluator:evaluator,
            builder:&builder,nextEntityID:&nextEntityID,context:&context)
    }
}
