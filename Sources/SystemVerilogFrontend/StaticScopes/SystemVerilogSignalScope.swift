import LogicIR
import LogicKernelCore

package struct SystemVerilogSignalScope: Sendable {
    internal final class Storage: Sendable {
        let parent: SystemVerilogSignalScope?
        let bindings: [SystemVerilogSignalBinding]
        init(parent: SystemVerilogSignalScope?, bindings: consuming [SystemVerilogSignalBinding]) {
            self.parent = parent; self.bindings = bindings
        }
    }
    package let constants: SystemVerilogConstantScope
    internal let storage: Storage
    @available(macOS 26.0, *)
    package static func bind(_ constants: borrowing SystemVerilogConstantScope,
        parent: Self? = nil, signals: consuming [SystemVerilogSignalBinding],
        context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try context.checkpoint()
        guard constants.storage.parent?.storage === parent?.constants.storage else {
            throw .invalidInput("Signal and constant scope parent owners differ")
        }
        try validate(signals, in: constants, context: &context)
        _ = try context.reserveStorage(byteCount: try SystemVerilogConstantEvaluator.bytes(signals.count, MemoryLayout<SystemVerilogSignalBinding>.stride))
        return Self(constants: copy constants, storage: Storage(parent: parent, bindings: signals))
    }
    @available(macOS 26.0, *)
    internal borrowing func resolve(_ name: Int, reference: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) -> (type: SystemVerilogConstantType, value: LogicFourStateVector?, signal: RTLSignalIndex?) {
        var current: Self? = copy self
        while let scope = current {
            try context.charge(.workUnits)
            for entry in scope.constants.storage.entries {
                try context.charge(.workUnits)
                guard entry.symbol == name else { continue }
                if let constant = entry.value {return (constant.type, constant.value, nil)}
                for binding in scope.storage.bindings {
                    try context.charge(.workUnits)
                    let symbol = try Self.symbol(binding.declaration, syntax: scope.constants.defaults.bindings.syntax)
                    if symbol == name {return (binding.type, nil, binding.signal)}
                }
                throw try SystemVerilogConstantScope.failure(reference, in: constants.defaults.bindings.syntax,
                    "SV_EXPRESSION_NONVALUE_NAME", "Nearest declaration is not a resolved signal or constant")
            }
            current = scope.storage.parent
        }
        throw try SystemVerilogConstantScope.failure(reference, in: constants.defaults.bindings.syntax,
            "SV_EXPRESSION_UNRESOLVED_NAME", "Expression name has no resolved declaration")
    }
    private static func symbol(_ node: Int, syntax: borrowing SystemVerilogSyntaxTree) throws(LogicKernelError) -> Int {
        switch try syntax.node(at: node).kind {
        case .declaration(.variable, let name, _, _), .declaration(.net, let name, _, _), .port(_, let name, _, _):return name
        default:throw .invalidInput("Signal binding requires a runtime signal declaration")
        }
    }
    @available(macOS 26.0, *)
    private static func validate(_ signals: borrowing [SystemVerilogSignalBinding],
        in constants: borrowing SystemVerilogConstantScope, context: inout LogicKernelContext) throws(LogicKernelError) {
        let syntax = constants.defaults.bindings.syntax
        for index in signals.indices {
            let binding = signals[index]
            var direct = false
            for entry in constants.storage.entries {
                try context.charge(.workUnits)
                if entry.declaration == binding.declaration && entry.value == nil {direct = true;break}
            }
            guard binding.signal.rawValue >= 0, !binding.type.isIndefinite, direct else {
                throw .invalidInput("Runtime binding is not a direct runtime declaration")
            }
            let name = try symbol(binding.declaration, syntax: syntax)
            for earlier in 0..<index {
                try context.charge(.workUnits)
                guard try symbol(signals[earlier].declaration, syntax: syntax) != name else {throw .invalidInput("Duplicate runtime signal binding")}
            }
            for entry in constants.storage.entries {
                try context.charge(.workUnits)
                guard entry.symbol == name else {continue}
                let typeNode: Int?
                switch try syntax.node(at: entry.declaration).kind {
                case .declaration(.variable, _, let type, _), .declaration(.net, _, let type, _):typeNode = type
                case .port(let direction, _, let type, _):
                    if direction == nil && type == nil {continue}
                    typeNode = type
                default:throw .invalidInput("A runtime signal cannot substitute a constant or scope name")
                }
                let expected = try SystemVerilogConstantEvaluator.withExpressionWorkspace(constants.defaults, scope: copy constants, context: &context) {
                    (evaluator, context) throws(LogicKernelError) in
                    try evaluator.declarationType(typeNode, inferred:nil, context:&context)
                }
                try context.charge(.workUnits,amount:UInt64(expected.dimensions.count))
                guard expected.width == binding.type.width, expected.isSigned == binding.type.isSigned,
                      expected.dimensions == binding.type.dimensions else {throw .invalidInput("Runtime signal type differs from its declaration")}
            }
        }
        for entry in constants.storage.entries {
            try context.charge(.workUnits)
            if entry.value != nil {continue}
            let runtime: Bool
            switch try syntax.node(at: entry.declaration).kind {
            case .declaration(.variable, _, _, _), .declaration(.net, _, _, _), .port:runtime = true
            default:runtime = false
            }
            if runtime {
                var found = false
                for index in signals.indices {
                    let binding = signals[index]
                    try context.charge(.workUnits)
                    if try symbol(binding.declaration,syntax:syntax) == entry.symbol {found = true;break}
                }
                guard found else {throw .invalidInput("A runtime declaration has no signal binding")}
            }
        }
    }
}
