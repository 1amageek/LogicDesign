import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogProgramCompiler {
    struct ControlWrite { let declaration: Int; let range: Range<Int>; let value: LogicFourStateVector }

    enum TargetOffset {
        case constant(Int?)
        case runtime(SystemVerilogResolvedExpression)
    }

    borrowing func targetWidth(_ node: Int, scope: borrowing SystemVerilogSignalScope,
        context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        try SystemVerilogConstantEvaluator.withExpressionWorkspace(scope.constants.defaults,
            scope: scope.constants, signals: copy scope, writableRoot: node, context: &context) {
            (evaluator, _) throws(LogicKernelError) in try evaluator.metadata(node).type.width.value
        }
    }

    mutating func assignment(target node: Int, rhs: SystemVerilogResolvedExpression,
        timing: RTLResolvedStatement.Timing, scope: inout SystemVerilogSignalScope, namespace: UInt64,
        procedural: Bool, knownRHS: LogicFourStateVector? = nil, context: inout LogicKernelContext) throws(LogicKernelError) -> RTLStatementIndex {
        let owner = scope
        return try SystemVerilogConstantEvaluator.withExpressionWorkspace(owner.constants.defaults,
            scope: owner.constants, signals: owner, writableRoot: node, context: &context) {
            (evaluator, context) throws(LogicKernelError) in
            let offsetBytes = try SystemVerilogConstantEvaluator.bytes(evaluator.syntax.nodeCount, MemoryLayout<TargetOffset?>.stride)
            let writeBytes = try SystemVerilogConstantEvaluator.bytes(capacity.children, MemoryLayout<RTLStatementIndex>.stride + MemoryLayout<ControlWrite>.stride)
            let bytes = offsetBytes.addingReportingOverflow(writeBytes)
            guard !bytes.overflow else { throw .invalidInput("Atomic assignment workspace overflow") }
            let scratch = try context.reserveStorage(byteCount: bytes.partialValue)
            let result: RTLStatementIndex
            do throws(LogicKernelError) {
                var offsets = [TargetOffset?](repeating: nil, count: evaluator.syntax.nodeCount)
                var writes: [RTLStatementIndex] = []; writes.reserveCapacity(capacity.children)
                var updates: [ControlWrite] = []; updates.reserveCapacity(capacity.children)
                let converted = try converted(rhs, width: evaluator.metadata(node).type.width.value,
                    node: node, scope: owner, context: &context)
                try writeTarget(node, bit: nil, rhs: converted, known: knownRHS, predicate: nil, timing: timing,
                    scope: owner, procedural: procedural, evaluator: &evaluator, offsets: &offsets,
                    writes: &writes, updates: &updates, context: &context)
                for update in updates {
                    guard let old = try scope.frozenControl(update.declaration, context: &context) else { throw .invalidModel("Control update lost its owner") }
                    var value = update.value
                    if update.range.lowerBound > 0 {
                        let low = try old.value.slicingBinary(offset: 0, width: LogicBitWidth(update.range.lowerBound), context: &context)
                        value = try value.concatenatingBinary(low, context: &context)
                    }
                    if update.range.upperBound < old.type.width.value {
                        let high = try old.value.slicingBinary(offset: update.range.upperBound, width: LogicBitWidth(old.type.width.value - update.range.upperBound), context: &context)
                        value = try high.concatenatingBinary(value, context: &context)
                    }
                    scope = try scope.replacingControl(update.declaration, with: value, context: &context)
                }
                result = try builder.addAssignmentGroup(id: id(), body: writes,
                    origin: Self.origin(node, syntax: evaluator.syntax), context: &context)
            } catch { try context.releaseStorage(scratch); throw error }
            try context.releaseStorage(scratch); return result
        }
    }

    private mutating func writeTarget(_ node: Int, bit: Int?, rhs: SystemVerilogResolvedExpression, known: LogicFourStateVector?,
        predicate: RTLExpressionIndex?, timing: RTLResolvedStatement.Timing,
        scope: borrowing SystemVerilogSignalScope, procedural: Bool,
        evaluator: inout SystemVerilogConstantEvaluator, offsets: inout [TargetOffset?],
        writes: inout [RTLStatementIndex], updates: inout [ControlWrite], context: inout LogicKernelContext) throws(LogicKernelError) {
        try enter(node, syntax: evaluator.syntax, context: &context); defer { depth -= 1 }
        let type = try evaluator.metadata(node).type
        if let bit, !(0..<type.width.value).contains(bit) { return }
        switch try evaluator.syntax.node(at: node).kind {
        case .identifier(let name):
            guard let entry = try scope.constants.lookup(name, context: &context) else { throw .invalidModel("Assignment lost its declaration") }
            let range = bit.map { $0..<($0 + 1) } ?? (0..<type.width.value)
            let binding = try runtimeBinding(name, in: scope, context: &context)
            if entry.value != nil {
                guard !entry.isGenerateConstant,
                      case .declaration(.variable, _, _, _) = try evaluator.syntax.node(at: entry.declaration).kind else {
                    throw try Self.failure(node, scope: scope, "SV_CONSTANT_ASSIGNMENT", "A constant cannot be assigned")
                }
                guard case .blocking = timing, predicate == nil, let known else {
                    throw try Self.failure(node, scope: scope, "SV_RUNTIME_LOOP_CONTROL", "Static loop updates require known blocking values and addresses")
                }
                guard updates.count < capacity.children else { throw .invalidInput("Atomic control-update capacity exhausted") }
                updates.append(ControlWrite(declaration: entry.declaration, range: range, value: known))
                if binding == nil { return }
            }
            guard let binding else { throw .invalidModel("Assignment lost its signal") }
            switch try evaluator.syntax.node(at: binding.declaration).kind {
            case .port(.input, _, _, _): throw try Self.failure(node, scope: scope, "SV_INPUT_ASSIGNMENT", "An input port cannot be assigned by its module")
            default: break
            }
            guard !procedural || binding.storage == .variable else {
                throw try Self.failure(node, scope: scope, "SV_PROCEDURAL_NET_WRITE", "Procedural assignments require a variable")
            }
            let value = try converted(rhs, width: range.count, node: node, scope: scope, context: &context)
            var write = try assign(binding.signal, range: range, value: value.index, timing: timing, node: node, scope: scope, context: &context)
            if let predicate {
                write = try builder.addStatement(RTLResolvedStatement(id: id(), operation: .conditional(condition: predicate, ifTrue: write, ifFalse: nil), origin: Self.origin(node, syntax: evaluator.syntax)), context: &context)
            }
            guard writes.count < capacity.children else { throw .invalidInput("Atomic assignment child capacity exhausted") }
            writes.append(write)
        case .concatenate(let children):
            guard bit == nil else { throw try Self.failure(node, scope: scope, "SV_ASSIGNMENT_TARGET", "A selected concatenation is not an assignable variable") }
            var remaining = type.width.value
            for offset in children {
                try context.charge(.workUnits)
                let child = try evaluator.syntax.child(at: offset)
                let width = try evaluator.metadata(child).type.width.value
                remaining -= width
                let value = try slice(rhs, offset: remaining, width: width, node: node, scope: scope, context: &context)
                let selectedKnown = try known?.slicingBinary(offset: remaining, width: LogicBitWidth(width), context: &context)
                try writeTarget(child, bit: nil, rhs: value, known: selectedKnown, predicate: predicate, timing: timing, scope: scope,
                    procedural: procedural, evaluator: &evaluator, offsets: &offsets, writes: &writes, updates: &updates, context: &context)
            }
        case .select(_, let base, let index, _):
            if offsets[node] == nil {
                let metadata = try evaluator.metadata(node)
                if let dynamic = metadata.dynamicSelection {
                    let indexType = try evaluator.metadata(index).type
                    if try !evaluator.metadata(index).containsRuntime {
                        let value = try evaluator.evaluateExpression(index, width: indexType.width.value, signed: indexType.isSigned, context: &context)
                        offsets[node] = .constant(try dynamic.constantOffset(value, signed: indexType.isSigned, context: &context))
                    } else {
                        let input = try expression(index, scope: scope, context: &context)
                        let scratch = try context.reserveStorage(byteCount: UInt64(MemoryLayout<RTLExpressionIndex>.stride * 2))
                        let normalized: SystemVerilogResolvedExpression
                        do throws(LogicKernelError) {
                            var emitter = SystemVerilogExpressionEmission(); emitter.inputs.reserveCapacity(2)
                            normalized = try emitter.normalizedOffset(input, selection: dynamic, node: node,
                                evaluator: evaluator, builder: &builder, nextEntityID: &nextEntityID, context: &context)
                        } catch { try context.releaseStorage(scratch); throw error }
                        try context.releaseStorage(scratch); offsets[node] = .runtime(normalized)
                    }
                } else { offsets[node] = .constant(metadata.offset) }
            }
            guard let selected = offsets[node] else { throw .invalidModel("Missing target normalization") }
            let baseWidth = try evaluator.metadata(base).type.width.value
            let bits = bit.map { $0..<($0+1) } ?? (0..<type.width.value)
            for selectedBit in bits {
                try context.charge(.workUnits)
                let sourceBit = bit == nil ? selectedBit : 0
                let value = try slice(rhs, offset: sourceBit, width: 1, node: node, scope: scope, context: &context)
                let selectedKnown = try known?.slicingBinary(offset: sourceBit, width: LogicBitWidth(1), context: &context)
                switch selected {
                case .constant(let start):
                    guard let start else { continue }
                    let destination = start.addingReportingOverflow(selectedBit)
                    if !destination.overflow, (0..<baseWidth).contains(destination.partialValue) {
                        try writeTarget(base, bit: destination.partialValue, rhs: value, known: selectedKnown, predicate: predicate, timing: timing,
                            scope: scope, procedural: procedural, evaluator: &evaluator, offsets: &offsets, writes: &writes, updates: &updates, context: &context)
                    }
                case .runtime(let offset):
                    for destination in 0..<baseWidth {
                        try context.charge(.workUnits)
                        let required = destination - selectedBit
                        if !Self.represents(required, type: offset.type) { continue }
                        let test = try offsetCondition(offset, equals: required, predicate: predicate,
                            node: node, scope: scope, evaluator: evaluator, context: &context)
                        try writeTarget(base, bit: destination, rhs: value, known: selectedKnown, predicate: test, timing: timing,
                            scope: scope, procedural: procedural, evaluator: &evaluator, offsets: &offsets, writes: &writes, updates: &updates, context: &context)
                    }
                }
            }
        default: throw .invalidModel("Writable inference admitted an unsupported target")
        }
    }

    private static func represents(_ value: Int, type: WordLogicType) -> Bool {
        let width = type.width.value
        if type.isSigned {
            if width >= Int.bitWidth { return true }
            let limit = 1 << (width - 1); return value >= -limit && value < limit
        }
        if value < 0 { return false }
        return width >= Int.bitWidth - 1 || value < (1 << width)
    }
    private mutating func slice(_ value: SystemVerilogResolvedExpression, offset: Int, width: Int,
        node: Int, scope: borrowing SystemVerilogSignalScope, context: inout LogicKernelContext)
        throws(LogicKernelError) -> SystemVerilogResolvedExpression {
        if offset == 0, width == value.type.width.value { return value }
        return try emit(.compute(.slice(offset: offset)), type: WordLogicType(width: LogicBitWidth(width)),
            a: value.index, node: node, scope: scope, context: &context)
    }
    private mutating func offsetCondition(_ offset: SystemVerilogResolvedExpression, equals value: Int,
        predicate: RTLExpressionIndex?, node: Int, scope: borrowing SystemVerilogSignalScope,
        evaluator: borrowing SystemVerilogConstantEvaluator, context: inout LogicKernelContext)
        throws(LogicKernelError) -> RTLExpressionIndex {
        var emitter = SystemVerilogExpressionEmission()
        let constant = try emitter.integerConstant(value, type: offset.type, node: node, evaluator: evaluator,
            builder: &builder, nextEntityID: &nextEntityID, context: &context)
        let boolean = WordLogicType(width: try LogicBitWidth(1))
        let equal = try emit(.compute(.equal), type: boolean, a: offset.index, b: constant.index, node: node, scope: scope, context: &context)
        if let predicate { return try emit(.compute(.and), type: boolean, a: predicate, b: equal.index, node: node, scope: scope, context: &context).index }
        return equal.index
    }
}
