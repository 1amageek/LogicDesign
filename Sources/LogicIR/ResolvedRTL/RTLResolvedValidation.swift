import CircuiteFoundation
import LogicKernelCore

internal enum RTLResolvedValidation {
    static func validate(_ tables: borrowing RTLResolvedTables, context: inout LogicKernelContext)
        throws(LogicKernelError) -> [RTLExpressionIndex] {
        var bits = 0
        for index in tables.signals.indices {
            try context.charge(.workUnits)
            let sum = bits.addingReportingOverflow(tables.signals[index].type.width.value)
            guard !sum.overflow else { throw .invalidModel("Resolved variable bit count overflow") }
            bits = sum.partialValue
        }
        var bytes: UInt64 = 0
        for (count, stride) in [(bits, MemoryLayout<Int>.stride),
                                (tables.signals.count + 1, 2 * MemoryLayout<Int>.stride),
                                (tables.statements.count, MemoryLayout<Bool>.stride + 2 * MemoryLayout<Int>.stride),
                                (tables.operands.count, 2 * MemoryLayout<Int>.stride),
                                (tables.signals.count, MemoryLayout<DesignEntityID>.stride),
                                (tables.expressions.count, MemoryLayout<DesignEntityID>.stride),
                                (tables.statements.count, MemoryLayout<DesignEntityID>.stride),
                                (tables.ports.count, MemoryLayout<DesignEntityID>.stride + MemoryLayout<String>.stride),
                                (tables.processes.count, MemoryLayout<DesignEntityID>.stride)] {
            let size = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
            let sum = bytes.addingReportingOverflow(size.partialValue)
            guard !size.overflow, !sum.overflow else { throw .invalidModel("Resolved validation storage overflow") }
            bytes = sum.partialValue
        }
        let reservation = try context.reserveStorage(byteCount: bytes)
        let result: [RTLExpressionIndex]
        do { result = try validateTables(tables, bitCount: bits, context: &context) }
        catch { try context.releaseStorage(reservation); throw error }
        try context.releaseStorage(reservation)
        return result
    }

    private static func validateTables(_ t: borrowing RTLResolvedTables, bitCount: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) -> [RTLExpressionIndex] {
        try identities(t.signals.count, idAt: { t.signals[$0].id }, context: &context)
        try identities(t.expressions.count, idAt: { t.expressions[$0].id }, context: &context)
        try identities(t.statements.count, idAt: { t.statements[$0].id }, context: &context)
        try identities(t.ports.count, idAt: { t.ports[$0].id }, context: &context)
        try identities(t.processes.count, idAt: { t.processes[$0].id }, context: &context)
        for index in t.signals.indices {
            try context.charge(.workUnits)
            let signal = t.signals[index]
            if let initial = signal.initialValue {
                guard !signal.isInput, initial.width == signal.type.width else { throw .invalidModel("Invalid resolved initial value") }
            }
        }
        var edges: [(Int, Int)] = []; edges.reserveCapacity(t.operands.count)
        var nextOperand = 0
        for index in t.expressions.indices {
            try context.charge(.workUnits)
            let expression = t.expressions[index]
            try owned(expression.operands, next: nextOperand, count: t.operands.count)
            nextOperand = expression.operands.upperBound
            for offset in expression.operands {
                try context.charge(.workUnits)
                let source = t.operands[offset].rawValue
                try reference(source, count: t.expressions.count)
                edges.append((source, index))
            }
            switch expression.operation {
            case .read(let signal):
                try reference(signal.rawValue, count: t.signals.count)
                guard expression.operands.isEmpty, expression.type == t.signals[signal.rawValue].type else {
                    throw .invalidModel("Resolved signal read type or arity mismatch")
                }
            case .constant(let value):
                guard expression.operands.isEmpty, expression.type.width == value.width else {
                    throw .invalidModel("Resolved constant type or arity mismatch")
                }
            case .compute(let opcode):
                try WordOperationValidation.validate(opcode, result: expression.type, operandCount: expression.operands.count,
                    typeAt: { t.expressions[t.operands[expression.operands.lowerBound + $0].rawValue].type }, context: &context)
            case .caseEqual:
                try WordOperationValidation.validate(.equal, result: expression.type, operandCount: expression.operands.count,
                    typeAt: { t.expressions[t.operands[expression.operands.lowerBound + $0].rawValue].type }, context: &context)
            case .dynamicSelect:
                guard expression.operands.count == 2, !expression.type.isSigned else {
                    throw .invalidModel("Resolved dynamic selection requires vector, offset and unsigned result")
                }
            }
        }
        guard nextOperand == t.operands.count else { throw .invalidModel("Unowned resolved operands") }
        try statements(t, context: &context)
        try ports(t, context: &context)
        try processes(t, bitCount: bitCount, context: &context)
        return try LogicTopology.order(nodeCount: t.expressions.count, edges: edges,
                                       makeIndex: RTLExpressionIndex.init, context: &context)
    }

    private static func statements(_ t: borrowing RTLResolvedTables, context: inout LogicKernelContext) throws(LogicKernelError) {
        var nextMatch = 0
        for index in t.caseItems.indices {
            try context.charge(.workUnits)
            let item = t.caseItems[index]
            try owned(item.matches, next: nextMatch, count: t.caseMatches.count)
            guard !item.matches.isEmpty else { throw .invalidModel("Empty resolved case match list") }
            nextMatch = item.matches.upperBound
            try reference(item.body.rawValue, count: t.statements.count)
            for offset in item.matches {
                try context.charge(.workUnits)
                try reference(t.caseMatches[offset].rawValue, count: t.expressions.count)
            }
        }
        guard nextMatch == t.caseMatches.count else { throw .invalidModel("Unowned resolved case matches") }
        var nextChild = 0; var nextItem = 0
        for index in t.statements.indices {
            try context.charge(.workUnits)
            switch t.statements[index].operation {
            case .assignment(let target, let selection, let value, _):
                try reference(target.rawValue, count: t.signals.count)
                try reference(value.rawValue, count: t.expressions.count)
                guard !t.signals[target.rawValue].isInput, selection.lowerBound >= 0, !selection.isEmpty,
                      selection.upperBound <= t.signals[target.rawValue].type.width.value,
                      t.expressions[value.rawValue].type.width.value == selection.count else {
                    throw located(.invalidModel("Invalid resolved assignment target, range or width"),
                        code: .trusted("LOGIC_RTL_INVALID_ASSIGNMENT"), origin: t.statements[index].origin)
                }
            case .block(let children), .assignmentGroup(let children):
                try owned(children, next: nextChild, count: t.children.count); nextChild = children.upperBound
                for offset in children { try context.charge(.workUnits); try reference(t.children[offset].rawValue, count: index) }
            case .conditional(let condition, let ifTrue, let ifFalse):
                try boolean(condition, tables: t); try reference(ifTrue.rawValue, count: index)
                if let ifFalse { try reference(ifFalse.rawValue, count: index) }
            case .caseStatement(let selector, let items, let fallback):
                try reference(selector.rawValue, count: t.expressions.count)
                try owned(items, next: nextItem, count: t.caseItems.count); nextItem = items.upperBound
                if let fallback { try reference(fallback.rawValue, count: index) }
                for item in items {
                    try context.charge(.workUnits)
                    try reference(t.caseItems[item].body.rawValue, count: index)
                    for match in t.caseItems[item].matches {
                        try context.charge(.workUnits)
                        guard t.expressions[t.caseMatches[match].rawValue].type == t.expressions[selector.rawValue].type else {
                            throw .invalidModel("Resolved case comparison type mismatch")
                        }
                    }
                }
            case .empty: break
            }
        }
        guard nextChild == t.children.count, nextItem == t.caseItems.count else { throw .invalidModel("Unowned resolved statements or cases") }
        for index in t.statements.indices {
            if case .assignmentGroup = t.statements[index].operation { _ = try assignmentGroup(index, tables: t, context: &context) }
        }
    }

    private static func ports(_ t: borrowing RTLResolvedTables, context: inout LogicKernelContext) throws(LogicKernelError) {
        var names = Set<String>(); names.reserveCapacity(t.ports.count)
        var inputs = [Bool](repeating: false, count: t.signals.count)
        for index in t.ports.indices {
            let port = t.ports[index]
            try context.charge(.workUnits, amount: UInt64(port.name.utf8.count) + 1)
            try reference(port.signal.rawValue, count: t.signals.count)
            guard !port.name.isEmpty, names.insert(port.name).inserted else { throw .invalidModel("Empty or duplicate resolved port name") }
            if port.direction == .input {
                guard t.signals[port.signal.rawValue].isInput, !inputs[port.signal.rawValue] else { throw .invalidModel("Invalid resolved input binding") }
                inputs[port.signal.rawValue] = true
            }
        }
        for index in t.signals.indices {
            try context.charge(.workUnits)
            if t.signals[index].isInput && !inputs[index] { throw .invalidModel("Unbound resolved input") }
        }
    }

    private static func processes(_ t: borrowing RTLResolvedTables, bitCount: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) {
        var offsets = [Int](repeating: 0, count: t.signals.count + 1)
        for index in t.signals.indices { try context.charge(.workUnits); offsets[index + 1] = offsets[index] + t.signals[index].type.width.value }
        var writers = [Int](repeating: -1, count: bitCount)
        var visited = [Bool](repeating: false, count: t.statements.count)
        var pending: [Int] = []; pending.reserveCapacity(t.statements.count)
        var clock: RTLExpressionIndex?; var edge: BitStateControl.Edge?; var hasLatch = false
        for processIndex in t.processes.indices {
            try context.charge(.workUnits)
            let process = t.processes[processIndex]
            try reference(process.body.rawValue, count: t.statements.count)
            switch process.control {
            case .flipFlop(let signal, let selectedEdge, let reset):
                guard !hasLatch else { throw located(.unsupported("Mixed explicit FF and latch RTL profile"), code: .trusted("LOGIC_RTL_UNSUPPORTED_PROFILE"), origin: process.origin) }
                try boolean(signal, tables: t)
                if let clock, clock != signal { throw located(.unsupported("Multiple resolved RTL clocks"), code: .trusted("LOGIC_RTL_UNSUPPORTED_PROFILE"), origin: process.origin) }
                if let edge, edge != selectedEdge { throw located(.unsupported("Multiple resolved RTL clock edges"), code: .trusted("LOGIC_RTL_UNSUPPORTED_PROFILE"), origin: process.origin) }
                clock = signal; edge = selectedEdge
                if let reset { try boolean(reset.signal, tables: t) }
            case .latch:
                guard clock == nil else { throw located(.unsupported("Mixed explicit latch and FF RTL profile"), code: .trusted("LOGIC_RTL_UNSUPPORTED_PROFILE"), origin: process.origin) }
                hasLatch = true
            case .continuous:
                switch t.statements[process.body.rawValue].operation {
                case .assignment(_, _, _, .blocking): break
                case .assignmentGroup:
                    guard try assignmentGroup(process.body.rawValue, tables: t, context: &context) else {
                        throw .invalidModel("Continuous assignment group contains a nonblocking write")
                    }
                default: throw .invalidModel("Continuous RTL process must contain one blocking assignment or assignment group")
                }
            case .combinational, .levelSensitive: break
            }
            for index in visited.indices { try context.charge(.workUnits); visited[index] = false }
            pending.removeAll(keepingCapacity: true)
            pending.append(process.body.rawValue); visited[process.body.rawValue] = true
            while let index = pending.popLast() {
                try context.charge(.workUnits)
                switch t.statements[index].operation {
                case .assignment(let target, let selection, _, _):
                    for bit in selection {
                        try context.charge(.workUnits)
                        let location = offsets[target.rawValue] + bit
                        guard writers[location] == -1 || writers[location] == processIndex else { throw located(.invalidModel("Overlapping resolved RTL process drivers"),
                            code: .trusted("LOGIC_RTL_MULTIPLE_DRIVERS"), origin: t.statements[index].origin) }
                        writers[location] = processIndex
                    }
                case .block(let children), .assignmentGroup(let children):
                    for offset in children {
                        try context.charge(.workUnits)
                        append(t.children[offset].rawValue, pending: &pending, visited: &visited)
                    }
                case .conditional(_, let ifTrue, let ifFalse):
                    append(ifTrue.rawValue, pending: &pending, visited: &visited)
                    if let ifFalse { append(ifFalse.rawValue, pending: &pending, visited: &visited) }
                case .caseStatement(_, let items, let fallback):
                    for item in items { try context.charge(.workUnits); append(t.caseItems[item].body.rawValue, pending: &pending, visited: &visited) }
                    if let fallback { append(fallback.rawValue, pending: &pending, visited: &visited) }
                case .empty: break
                }
            }
        }
    }

    private static func assignmentGroup(_ root: Int, tables t: borrowing RTLResolvedTables,
        context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        var pending: [Int] = []; pending.reserveCapacity(t.statements.count); pending.append(root)
        var visited = [Bool](repeating: false, count: t.statements.count); visited[root] = true
        var blocking = true
        while let node = pending.popLast() {
            try context.charge(.workUnits)
            switch t.statements[node].operation {
            case .assignment(_, _, _, let timing): if case .nonBlocking = timing { blocking = false }
            case .assignmentGroup(let children):
                for offset in children { try context.charge(.workUnits); append(t.children[offset].rawValue, pending: &pending, visited: &visited) }
            case .conditional(_, let yes, let no):
                append(yes.rawValue, pending: &pending, visited: &visited)
                if let no { append(no.rawValue, pending: &pending, visited: &visited) }
            case .empty: break
            case .block, .caseStatement: throw .invalidModel("Assignment group contains a sequential program")
            }
        }
        return blocking
    }

    private static func append(_ index: Int, pending: inout [Int], visited: inout [Bool]) {
        if !visited[index] { visited[index] = true; pending.append(index) }
    }
    private static func boolean(_ index: RTLExpressionIndex, tables: borrowing RTLResolvedTables) throws(LogicKernelError) {
        try reference(index.rawValue, count: tables.expressions.count)
        let type = tables.expressions[index.rawValue].type
        guard type.width.value == 1, !type.isSigned else { throw .invalidModel("Resolved control must be unsigned one-bit") }
    }
    private static func reference(_ index: Int, count: Int) throws(LogicKernelError) {
        guard index >= 0, index < count else { throw .invalidModel("Resolved reference outside table or recursive statement") }
    }
    private static func owned(_ range: Range<Int>, next: Int, count: Int) throws(LogicKernelError) {
        guard range.lowerBound == next, range.upperBound <= count else { throw .invalidModel("Invalid or unowned resolved table range") }
    }
    private static func identities(_ count: Int, idAt: (Int) -> DesignEntityID, context: inout LogicKernelContext) throws(LogicKernelError) {
        var identities = Set<DesignEntityID>(); identities.reserveCapacity(count)
        for index in 0..<count { try context.charge(.workUnits); guard identities.insert(idAt(index)).inserted else { throw .invalidModel("Duplicate resolved entity identity") } }
    }
    private static func located(_ error: LogicKernelError, code: DiagnosticCode,
                                origin: LogicKernelSourceRange?) -> LogicKernelError {
        guard let origin else { return error }
        switch error {
        case .unsupported(let message), .invalidModel(let message):
            return .sourceFailure(code: code, source: origin, message: message)
        default: return error
        }
    }

}
