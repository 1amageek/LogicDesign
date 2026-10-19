import CircuiteFoundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
package struct SystemVerilogConstantEvaluator: ~Copyable {
    internal struct Info {
        private let resolvedType: SystemVerilogConstantType?
        var isEmpty: Bool { resolvedType == nil }
        var type: SystemVerilogConstantType {
            get throws(LogicKernelError) {
                guard let resolvedType else { throw .invalidModel("Empty repetition has no standalone integral type") }
                return resolvedType
            }
        }
        var signal: RTLSignalIndex?
        var containsRuntime = false
        var dynamicSelection: SystemVerilogDynamicSelection?
        var literal: LogicFourStateVector?
        var fill: Bool?
        var offset = 0
        var repetitions = 0
        init(type: SystemVerilogConstantType, literal: LogicFourStateVector? = nil,
             fill: Bool? = nil, offset: Int = 0, repetitions: Int = 0) {
            resolvedType = type; self.literal = literal; self.fill = fill
            self.offset = offset; self.repetitions = repetitions
        }
        init() { resolvedType = nil }
    }
    internal struct Frame {
        let node: Int
        let width: Int
        let signed: Bool
        let finish: Bool
    }
    internal let bindings: SystemVerilogParameterBindings
    internal var syntax: SystemVerilogSyntaxTree { bindings.syntax }
    internal var parameters: [SystemVerilogConstant?]
    internal var info: [Info?]
    internal var overrides: [SystemVerilogConstantExpression?] = []
    internal let allowModuleLookup: Bool
    internal var signalScope: SystemVerilogSignalScope? = nil
    internal var lexicalParent: SystemVerilogConstantScope? = nil
    internal var lexicalEntries: [SystemVerilogScopeEntry] = []
    internal var pending: [Int] = []
    internal var frames: [Frame] = []
    internal var values: [LogicFourStateVector] = []
    internal var writableSelections: [Bool] = []

    package static func evaluate(_ bindings: borrowing SystemVerilogParameterBindings,
        overrides: borrowing [SystemVerilogParameterOverride] = [],
        context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogParameterDefaults {
        try context.checkpoint()
        let count = bindings.syntax.nodeCount
        let published = try bytes(count, MemoryLayout<SystemVerilogConstant?>.stride)
        let perNode = workspaceStride + (overrides.isEmpty ? 0 : MemoryLayout<SystemVerilogConstantExpression?>.stride)
        let temporary = try bytes(count, perNode)
        let total = published.addingReportingOverflow(temporary)
        guard !total.overflow else { throw .invalidInput("Constant table storage overflow") }
        try context.require(.managedStorageBytes, amount: total.partialValue)
        _ = try context.reserveStorage(byteCount: published)
        let scratch = try context.reserveStorage(byteCount: temporary)
        let result: SystemVerilogParameterDefaults
        do throws(LogicKernelError) {
            var evaluator = Self(bindings: copy bindings,
                parameters: [SystemVerilogConstant?](repeating: nil, count: count),
                info: [Info?](repeating: nil, count: count), allowModuleLookup: false)
            evaluator.pending.reserveCapacity(count * 2); evaluator.frames.reserveCapacity(count * 2)
            evaluator.values.reserveCapacity(count)
            try evaluator.admitOverrides(overrides, context: &context)
            for ordinal in 0..<bindings.count {
                try evaluator.evaluateDeclaration(bindings.declaration(at: ordinal), context: &context)
            }
            result = evaluator.publish()
        } catch { try context.releaseStorage(scratch); throw error }
        try context.releaseStorage(scratch)
        return result
    }
    internal static var workspaceStride: Int {
        MemoryLayout<Info?>.stride + MemoryLayout<Int>.stride * 2
            + MemoryLayout<Frame>.stride * 2 + MemoryLayout<LogicFourStateVector>.stride
    }
    internal static func bytes(_ count: Int, _ stride: Int) throws(LogicKernelError) -> UInt64 {
        guard count <= Int.max / 2 else { throw .invalidInput("Constant table capacity overflow") }
        let bytes = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
        guard !bytes.overflow else { throw .invalidInput("Constant table storage overflow") }
        return bytes.partialValue
    }
    private consuming func publish() -> SystemVerilogParameterDefaults {
        SystemVerilogParameterDefaults(bindings: bindings, values: parameters)
    }
    internal borrowing func failure(_ node: Int, _ code: String, _ message: String)
        throws(LogicKernelError) -> LogicKernelError {
        let range = try syntax.node(at: node).byteRange
        return .sourceFailure(code: .trusted(code), source: try syntax.source.origin(for: range), message: message)
    }
    internal borrowing func metadata(_ node: Int) throws(LogicKernelError) -> Info {
        guard info.indices.contains(node), let result = info[node] else {
            throw .invalidModel("Constant expression metadata is unavailable")
        }
        return result
    }
    internal mutating func evaluateDeclaration(_ node: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        parameters[node] = try declarationValue(node, context: &context)
    }
    internal mutating func declarationValue(_ node: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) -> SystemVerilogConstant {
        guard case .declaration(_, _, let typeNode, let initializer) = try syntax.node(at: node).kind,
              let initializer else { throw .invalidModel("Expected bound parameter default") }
        if overrides.isEmpty || overrides[node] == nil { try requireConstantSyntax(initializer, context: &context) }
        let replacement = overrides.isEmpty ? nil : overrides[node]
        let inferred: SystemVerilogConstantType
        if let replacement { inferred = replacement.type }
        else {
            try infer(initializer, context: &context)
            guard try !metadata(initializer).isEmpty else {
                throw try failure(initializer, "SV_CONSTANT_EMPTY", "An empty repetition requires a nonempty containing concatenation")
            }
            inferred = try metadata(initializer).type
        }
        let resultType = try declarationType(typeNode, inferred: inferred, context: &context)
        try context.observeBitWidth(UInt64(resultType.width.value))
        let evaluated: LogicFourStateVector
        if let replacement { evaluated = try replacement.evaluate(width: resultType.width.value, context: &context) }
        else { evaluated = try evaluateExpression(initializer, width: resultType.width.value, signed: inferred.isSigned, context: &context) }
        let converted = try evaluated.resizedBinary(to: resultType.width, signExtend: inferred.isSigned, context: &context)
        try context.charge(.expansion)
        let initializerRange = try syntax.node(at: initializer).byteRange
        let origin: LogicKernelSourceRange
        if let replacement { origin = replacement.origin }
        else { origin = try syntax.source.origin(for: initializerRange) }
        return SystemVerilogConstant(type: resultType, value: converted, origin: origin)
    }
    internal mutating func declarationType(_ typeNode: Int?, inferred: SystemVerilogConstantType?,
        context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogConstantType {
        let fallback = try SystemVerilogConstantType(width: 1)
        var resultType = inferred ?? fallback
        if let typeNode {
            guard case .type(let base, let signed, let dimensions, _, let explicit) = try syntax.node(at: typeNode).kind else {
                throw .invalidModel("Parameter type syntax is malformed")
            }
            var ranges: [SystemVerilogPackedDimension] = []
            _ = try context.reserveStorage(byteCount: UInt64(dimensions.count) * UInt64(MemoryLayout<SystemVerilogPackedDimension>.stride))
            ranges.reserveCapacity(dimensions.count)
            var width = base == .int || base == .integer ? 32 : 1
            for offset in dimensions {
                let rangeNode = try syntax.child(at: offset)
                guard case .packedRange(let left, let right) = try syntax.node(at: rangeNode).kind else {
                    throw .invalidModel("Parameter dimension syntax is malformed")
                }
                try requireConstantSyntax(left, context: &context); try requireConstantSyntax(right, context: &context)
                try infer(left, context: &context); try infer(right, context: &context)
                let leftValue = try integer(left, context: &context)
                let rightValue = try integer(right, context: &context)
                let range: SystemVerilogPackedDimension
                do throws(LogicKernelError) {
                    range = try SystemVerilogPackedDimension(left: leftValue, right: rightValue)
                } catch { throw try failure(rangeNode, "SV_CONSTANT_DIMENSION", "Packed dimension is not representable") }
                let product = width.multipliedReportingOverflow(by: range.count)
                guard !product.overflow else { throw try failure(rangeNode, "SV_CONSTANT_WIDTH", "Packed type width overflow") }
                width = product.partialValue; ranges.append(range)
                try context.observeBitWidth(UInt64(width))
            }
            if dimensions.isEmpty && !explicit { width = inferred.map { $0.isIndefinite ? 32 : $0.width.value } ?? 1 }
            resultType = try SystemVerilogConstantType(width: width,
                signed: signed ?? (base == .int || base == .integer), dimensions: ranges)
        } else if let inferred, inferred.isIndefinite {
            resultType = try SystemVerilogConstantType(width: max(32, inferred.width.value), signed: inferred.isSigned)
        } else if let inferred {
            resultType = try SystemVerilogConstantType(width: inferred.width.value, signed: inferred.isSigned)
        }
        return resultType
    }
    internal mutating func integer(_ node: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        let type = try metadata(node).type
        let value = try evaluateExpression(node, width: type.width.value, signed: type.isSigned, context: &context)
        do throws(LogicKernelError) { return try value.binaryInt(signed: type.isSigned, context: &context) }
        catch let error {
            if case .invalidModel = error { throw try failure(node, "SV_CONSTANT_INDEX", "Constant cannot be represented as a target index") }
            throw error
        }
    }
}
