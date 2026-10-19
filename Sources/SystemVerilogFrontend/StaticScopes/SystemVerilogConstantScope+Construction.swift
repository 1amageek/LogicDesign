import CircuiteFoundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogConstantScope {
    internal static func ownsModuleExpression(_ expression: Int,
        defaults: borrowing SystemVerilogParameterDefaults, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Bool {
        try context.checkpoint()
        let syntax = defaults.bindings.syntax
        let candidate = try syntax.node(at: expression).byteRange
        let module = try syntax.node(at: defaults.bindings.module).byteRange
        guard expression < defaults.bindings.module, candidate.lowerBound >= module.lowerBound,
              candidate.upperBound <= module.upperBound else { return false }
        for node in expression..<defaults.bindings.module {
            try context.charge(.workUnits)
            let current = try syntax.node(at: node)
            guard current.byteRange.lowerBound >= module.lowerBound,
                  current.byteRange.upperBound <= module.upperBound else { continue }
            if lexical(current.kind), contains(candidate, in: current.byteRange) { return false }
            switch current.kind {
            case .generateIf(_, let then, let otherwise):
                if try isBoundary(then, syntax: syntax), contains(candidate, in: try syntax.node(at: then).byteRange) { return false }
                if let otherwise, try isBoundary(otherwise, syntax: syntax), contains(candidate, in: try syntax.node(at: otherwise).byteRange) { return false }
            case .generateCase(_, let arms):
                for offset in arms {
                    try context.charge(.workUnits)
                    guard case .caseArm(_, let body) = try syntax.node(at: syntax.child(at: offset)).kind else {
                        throw .invalidModel("Malformed generate case scope")
                    }
                    if try isBoundary(body, syntax: syntax), contains(candidate, in: try syntax.node(at: body).byteRange) { return false }
                }
            default: break
            }
        }
        return true
    }
    private static func isBoundary(_ body: Int, syntax: borrowing SystemVerilogSyntaxTree)
        throws(LogicKernelError) -> Bool {
        switch try syntax.node(at: body).kind {
        case .generateIf, .generateCase: return false
        default: return true
        }
    }
    private static func contains(_ inner: Range<Int>, in outer: Range<Int>) -> Bool {
        inner.lowerBound >= outer.lowerBound && inner.upperBound <= outer.upperBound
    }
    private static func lexical(_ kind: SystemVerilogSyntaxNode.Kind) -> Bool {
        switch kind {
        case .block, .generateBlock, .forStatement, .generateFor: return true
        default: return false
        }
    }
    internal static func build(defaults: borrowing SystemVerilogParameterDefaults,
        container: Int, parent: Self?, iteration: LogicFourStateVector?,
        context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try context.checkpoint()
        let syntax = defaults.bindings.syntax
        _ = try syntax.node(at: container)
        let count = container + 1
        let payload = try SystemVerilogConstantEvaluator.bytes(count,
            MemoryLayout<SystemVerilogScopeEntry>.stride + MemoryLayout<Int>.stride)
        let admission = try context.reserveStorage(byteCount: payload)
        let result: Self
        do throws(LogicKernelError) {
            result = try construct(defaults: defaults, container: container, parent: parent,
                iteration: iteration, context: &context)
        } catch { try context.releaseStorage(admission); throw error }
        return result
    }
    private static func construct(defaults: borrowing SystemVerilogParameterDefaults,
        container: Int, parent: Self?, iteration: LogicFourStateVector?,
        context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        let syntax = defaults.bindings.syntax
        let root = try syntax.node(at: container)
        let count = container + 1
        var entries: [SystemVerilogScopeEntry] = []
        var children: [Int] = []
        entries.reserveCapacity(count); children.reserveCapacity(count)
        // Postorder syntax puts enclosing lexical nodes before their descendants in this scan.
        for node in (0...container).reversed() {
            try context.charge(.workUnits)
            let candidate = try syntax.node(at: node)
            guard candidate.byteRange.lowerBound >= root.byteRange.lowerBound,
                  candidate.byteRange.upperBound <= root.byteRange.upperBound else { continue }
            var nested = false
            for child in children {
                try context.charge(.workUnits)
                let range = try syntax.node(at: child).byteRange
                if node <= child && candidate.byteRange.lowerBound >= range.lowerBound &&
                    candidate.byteRange.upperBound <= range.upperBound { nested = true; break }
            }
            if nested { continue }
            if node != container && lexical(candidate.kind) {
                children.append(node)
                switch candidate.kind {
                case .block(let label?, _), .generateBlock(let label?, _):
                    entries.append(SystemVerilogScopeEntry(symbol: label, declaration: node, value: nil))
                default: break
                }
                continue
            }
            // Terminal conditional-generate bodies own scopes; direct nested controls share the parent.
            switch candidate.kind {
            case .generateIf(_, let then, let otherwise):
                if try isBoundary(then, syntax: syntax) { children.append(then) }
                if let otherwise, try isBoundary(otherwise, syntax: syntax) { children.append(otherwise) }
            case .generateCase(_, let arms):
                for offset in arms {
                    try context.charge(.workUnits)
                    guard case .caseArm(_, let body) = try syntax.node(at: syntax.child(at: offset)).kind else {
                        throw .invalidModel("Generate case contains another syntax kind")
                    }
                    if try isBoundary(body, syntax: syntax) { children.append(body) }
                }
            default: break
            }
            let symbol: Int
            switch candidate.kind {
            case .declaration(_, let name, _, _), .port(_, let name, _, _), .instance(_, let name, _, _): symbol = name
            default: continue
            }
            entries.append(SystemVerilogScopeEntry(symbol: symbol, declaration: node, value: nil))
        }
        entries.reverse()
        for child in children {
            try context.charge(.workUnits)
            let label: Int?
            switch try syntax.node(at: child).kind {
            case .block(let name, _), .generateBlock(let name, _): label = name
            default: label = nil
            }
            if let label {
                var present = false
                for entry in entries {
                    try context.charge(.workUnits)
                    if entry.declaration == child { present = true; break }
                }
                if !present { entries.append(SystemVerilogScopeEntry(symbol: label, declaration: child, value: nil)) }
            }
        }
        // The explicit generated block and its implicit genvar localparam share one scope.
        if let parent, case .generateFor(_, _, _, let body) = try syntax.node(at: parent.container).kind,
           body == container, case .generateBlock = root.kind {
            for entry in parent.storage.entries {
                try context.charge(.workUnits)
                guard entry.isGenerateConstant else { continue }
                guard entries.count < count else { throw .invalidModel("Generate body binding capacity exhausted") }
                entries.insert(entry, at: 0)
            }
        }
        for index in entries.indices {
            for earlier in 0..<index {
                try context.charge(.workUnits)
                guard entries[index].symbol == entries[earlier].symbol else { continue }
                let a = try syntax.node(at: entries[earlier].declaration).kind
                let b = try syntax.node(at: entries[index].declaration).kind
                // Non-ANSI header/body port declarations denote one signal; both remain blockers.
                if case .port(let firstDirection, _, let firstType, _) = a,
                   case .port(let secondDirection, _, let secondType, _) = b,
                   (firstDirection == nil && firstType == nil && secondDirection != nil) ||
                   (secondDirection == nil && secondType == nil && firstDirection != nil) { continue }
                if lexical(a), lexical(b), try mutuallyExclusive(entries[earlier].declaration,
                    entries[index].declaration, container: container, syntax: syntax, context: &context) { continue }
                throw try failure(entries[index].declaration, in: syntax, "SV_SCOPE_DUPLICATE_NAME", "A lexical name has more than one declaration")
            }
        }
        if parent == nil {
            for index in entries.indices {
                let declaration = entries[index].declaration
                if case .declaration(let kind, _, _, _) = try syntax.node(at: declaration).kind,
                   kind == .parameter || kind == .localParameter {
                    entries[index].value = try defaults.value(forDeclaration: declaration)
                }
            }
            return Self(defaults: copy defaults, container: container, parent: nil, entries: entries, children: children)
        }
        return try SystemVerilogConstantEvaluator.scope(defaults: defaults, container: container,
            parent: parent, entries: entries, children: children, iteration: iteration, context: &context)
    }
    private static func mutuallyExclusive(_ first: Int, _ second: Int, container: Int,
        syntax: borrowing SystemVerilogSyntaxTree, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        for node in max(first, second)..<container {
            try context.charge(.workUnits)
            switch try syntax.node(at: node).kind {
            case .generateIf(_, let then, let otherwise?):
                let a = try syntax.node(at: first).byteRange; let b = try syntax.node(at: second).byteRange
                let yes = try syntax.node(at: then).byteRange; let no = try syntax.node(at: otherwise).byteRange
                if (contains(a, in: yes) && contains(b, in: no)) || (contains(a, in: no) && contains(b, in: yes)) { return true }
            case .generateCase(_, let arms):
                var firstArm: Int?; var secondArm: Int?
                let a = try syntax.node(at: first).byteRange; let b = try syntax.node(at: second).byteRange
                for offset in arms {
                    try context.charge(.workUnits)
                    guard case .caseArm(_, let body) = try syntax.node(at: syntax.child(at: offset)).kind else {
                        throw .invalidModel("Malformed generate case scope")
                    }
                    let range = try syntax.node(at: body).byteRange
                    if contains(a, in: range) { firstArm = offset }
                    if contains(b, in: range) { secondArm = offset }
                }
                if let firstArm, let secondArm, firstArm != secondArm { return true }
            default: break
            }
        }
        return false
    }
    internal static func failure(_ node: Int, in syntax: borrowing SystemVerilogSyntaxTree,
        _ code: String, _ message: String) throws(LogicKernelError) -> LogicKernelError {
        let range = try syntax.node(at: node).byteRange
        return .sourceFailure(code: .trusted(code), source: try syntax.source.origin(for: range), message: message)
    }
}
