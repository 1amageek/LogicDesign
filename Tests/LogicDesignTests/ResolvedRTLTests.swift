import Testing
import CircuiteFoundation
import LogicIR
import LogicKernelCore

@Suite(.timeLimit(.minutes(1)))
struct ResolvedRTLTests {
    private struct Control: LogicRunControlling { func checkpoint() throws(LogicKernelError) {} }
    private struct Cancelled: LogicRunControlling { func checkpoint() throws(LogicKernelError) { throw .cancelled } }
    private func context(control: any LogicRunControlling = Control(), nodes: UInt64 = 1_000_000) throws -> LogicKernelContext {
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) })
        limits[.nodes] = nodes
        return LogicKernelContext(limits: try LogicKernelLimits(maximums: limits), control: control)
    }
    private func id(_ value: UInt64) throws -> DesignEntityID { try DesignEntityID(rawValue: value) }
    private func type(_ width: Int) throws -> WordLogicType { WordLogicType(width: try LogicBitWidth(width)) }
    private func builder(context: inout LogicKernelContext) throws -> ElaboratedRTLBuilder {
        try ElaboratedRTLBuilder(topModuleID: id(1024), capacity: RTLResolvedCapacity(signals: 4, expressions: 8, operands: 8,
            statements: 8, children: 8, caseItems: 4, caseMatches: 4, ports: 4, processes: 4), context: &context)
    }
    private func reject(_ builder: consuming ElaboratedRTLBuilder, context: inout LogicKernelContext) {
        do { _ = try builder.finish(context: &context); Issue.record("Invalid resolved program was published") }
        catch { }
    }
    @Test func assignmentGroupsRejectSequentialChildrenAndContinuousNBA() throws {
        for mode in 0..<4 {
            var run = try context(); var build = try builder(context: &run)
            let signal = try build.addSignal(RTLResolvedSignal(id: id(1), type: type(1)), context: &run)
            let value = try LogicFourStateVector(width: LogicBitWidth(1), valueWords: [1], unknownWords: [0])
            let rhs = try build.addExpression(id: id(1), type: type(1), operation: .constant(value), context: &run)
            var child = try build.addStatement(RTLResolvedStatement(id: id(1), operation: .assignment(target: signal,
                selection: 0..<1, value: rhs, timing: mode == 2 ? .nonBlocking : .blocking)), context: &run)
            if mode == 1 { child = try build.addBlock(id: id(2), body: [child], context: &run) }
            if mode == 3 {
                child = try build.addStatement(RTLResolvedStatement(id: id(2), operation: .caseStatement(selector: rhs, items: 0..<0, defaultBody: child)), context: &run)
            }
            let group = try build.addAssignmentGroup(id: id(3), body: [child], context: &run)
            try build.addProcess(RTLResolvedProcess(id: id(1), control: .continuous, body: group), context: &run)
            if mode == 0 { #expect(try build.finish(context: &run).statementCount == 2) }
            else { reject(build, context: &run) }
        }
    }

    @Test func orderedBlockingAndNBARemainProceduralWithForwardExpressions() throws {
        var context = try context(); var builder = try builder(context: &context)
        let artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
            hexadecimalValue: "a009b436ae3ecac5a7b12e02855ca1c389d442b177df51d784e3260e593033b8"), byteCount: 32)
        let origin = try LogicKernelSourceRange(artifactID: artifact, byteRange: 11..<17)
        let clock = try builder.addSignal(RTLResolvedSignal(id: id(1), type: type(1), isInput: true), context: &context)
        let state = try builder.addSignal(RTLResolvedSignal(id: id(2), type: type(129), origin: origin), context: &context)
        let clockRead = try builder.addExpression(id: id(1), type: type(1), operation: .read(clock), context: &context)
        let one = try LogicFourStateVector(width: LogicBitWidth(129), valueWords: [1, 0, 0], unknownWords: [0, 0, 0])
        let constant = try builder.addExpression(id: id(2), type: type(129), operation: .constant(one), context: &context)
        let inverse = try builder.addExpression(id: id(3), type: type(129), operation: .compute(.invert),
            inputs: [RTLExpressionIndex(3)], context: &context)
        _ = try builder.addExpression(id: id(4), type: type(129), operation: .read(state), context: &context)
        let first = try builder.addStatement(RTLResolvedStatement(id: id(1), operation: .assignment(
            target: state, selection: 0..<129, value: constant, timing: .blocking)), context: &context)
        let last = try builder.addStatement(RTLResolvedStatement(id: id(2), operation: .assignment(
            target: state, selection: 0..<129, value: inverse, timing: .nonBlocking)), context: &context)
        let body = try builder.addBlock(id: id(3), body: [first, last], context: &context)
        try builder.addProcess(RTLResolvedProcess(id: id(1), control: .flipFlop(clock: clockRead, edge: .rising,
            asynchronousReset: nil), body: body), context: &context)
        try builder.addPort(RTLResolvedPort(id: id(1), name: "clock", direction: .input, signal: clock), context: &context)
        try builder.addPort(RTLResolvedPort(id: id(2), name: "q", direction: .output, signal: state), context: &context)
        let design = try builder.finish(context: &context)
        #expect(design.topModuleID == (try id(1024)))
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        #expect(design.withExpressions { _, operands, order in operands[0] == RTLExpressionIndex(3) && order[3] == inverse })
        #expect(design.withProgram { signals, statements, children, _, _, _, processes in
            guard case .assignment(_, _, _, .blocking) = statements[0].operation,
                  case .assignment(_, _, _, .nonBlocking) = statements[1].operation else { return false }
            return signals[state.rawValue].initialValue == nil && signals[state.rawValue].origin == origin
                && children[0] == first && children[1] == last && processes[0].body == body
        })
        do {
            try design.withProgram { _, _, _, _, _, _, _ throws(LogicKernelError) in throw .deadlineExceeded }
            Issue.record("Typed callback error was lost")
        } catch { #expect(error == .deadlineExceeded) }
    }

    @Test func casePriorityAndFourStateSimulationConstantsRemainExplicit() throws {
        var context = try context(); var builder = try builder(context: &context)
        let variable = try builder.addSignal(RTLResolvedSignal(id: id(1), type: type(1)), context: &context)
        let unknown = try LogicFourStateVector(repeating: .unknown, width: LogicBitWidth(1), context: &context)
        let selector = try builder.addExpression(id: id(1), type: type(1), operation: .constant(unknown), context: &context)
        let equality = try builder.addExpression(id: id(2), type: type(1), operation: .caseEqual,
            inputs: [selector, selector], context: &context)
        let assign = try builder.addStatement(RTLResolvedStatement(id: id(1), operation: .assignment(
            target: variable, selection: 0..<1, value: equality, timing: .blocking)), context: &context)
        let empty = try builder.addStatement(RTLResolvedStatement(id: id(2), operation: .empty), context: &context)
        _ = try builder.addCaseItem(matches: [selector], body: assign, context: &context)
        _ = try builder.addCaseItem(matches: [selector], body: empty, context: &context)
        let body = try builder.addStatement(RTLResolvedStatement(id: id(3), operation: .caseStatement(
            selector: selector, items: 0..<2, defaultBody: empty)), context: &context)
        try builder.addProcess(RTLResolvedProcess(id: id(1), control: .combinational, body: body), context: &context)
        let design = try builder.finish(context: &context)
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        #expect(design.withProgram { _, _, _, items, matches, _, _ in
            items[0].body == assign && items[1].body == empty && matches[0] == matches[1]
        })
    }

    @Test func disjointBitDriversAreAdmittedButOverlapIsRejected() throws {
        for overlap in [false, true] {
            var context = try context(); var builder = try builder(context: &context)
            let variable = try builder.addSignal(RTLResolvedSignal(id: id(1), type: type(8)), context: &context)
            let zero = try LogicFourStateVector(repeating: .zero, width: LogicBitWidth(4), context: &context)
            let value = try builder.addExpression(id: id(1), type: type(4), operation: .constant(zero), context: &context)
            for index in 0..<2 {
                let start = index == 0 ? 0 : overlap ? 2 : 4
                let assignment = try builder.addStatement(RTLResolvedStatement(id: id(UInt64(index + 1)), operation: .assignment(
                    target: variable, selection: start..<(start + 4), value: value, timing: .blocking)), context: &context)
                try builder.addProcess(RTLResolvedProcess(id: id(UInt64(index + 1)), control: .continuous, body: assignment), context: &context)
            }
            if overlap { reject(builder, context: &context) }
            else { let design = try builder.finish(context: &context); #expect(design.processCount == 2) }
        }
    }

    @Test func expressionTypesReferencesAndCyclesCannotBypassPublication() throws {
        for mode in 0..<5 {
            var context = try context(); var builder = try builder(context: &context)
            let variable = try builder.addSignal(RTLResolvedSignal(id: id(1), type: type(8)), context: &context)
            switch mode {
            case 0: _ = try builder.addExpression(id: id(1), type: type(4), operation: .read(variable), context: &context)
            case 1:
                let value = try LogicFourStateVector(repeating: .zero, width: LogicBitWidth(4), context: &context)
                _ = try builder.addExpression(id: id(1), type: type(8), operation: .constant(value), context: &context)
            case 2: _ = try builder.addExpression(id: id(1), type: type(8), operation: .compute(.add), context: &context)
            case 3: _ = try builder.addExpression(id: id(1), type: type(8), operation: .compute(.invert), inputs: [RTLExpressionIndex(99)], context: &context)
            default: _ = try builder.addExpression(id: id(1), type: type(8), operation: .compute(.invert), inputs: [RTLExpressionIndex(0)], context: &context)
            }
            reject(builder, context: &context)
        }
    }

    @Test func assignmentRangesRecursionAndCaseOwnershipAreChecked() throws {
        for mode in 0..<7 {
            var context = try context(); var builder = try builder(context: &context)
            let variable = try builder.addSignal(RTLResolvedSignal(id: id(1), type: type(8), isInput: mode == 0), context: &context)
            if mode == 0 { try builder.addPort(RTLResolvedPort(id: id(1), name: "a", direction: .input, signal: variable), context: &context) }
            let value = try LogicFourStateVector(repeating: .zero, width: LogicBitWidth(8), context: &context)
            let expression = try builder.addExpression(id: id(1), type: type(8), operation: .constant(value), context: &context)
            switch mode {
            case 0...2:
                _ = try builder.addStatement(RTLResolvedStatement(id: id(1), operation: .assignment(
                    target: variable, selection: mode == 1 ? 0..<4 : mode == 2 ? -1..<7 : 0..<8,
                    value: expression, timing: .blocking)), context: &context)
            case 3: _ = try builder.addBlock(id: id(1), body: [RTLStatementIndex(0)], context: &context)
            case 4:
                let empty = try builder.addStatement(RTLResolvedStatement(id: id(1), operation: .empty), context: &context)
                _ = try builder.addStatement(RTLResolvedStatement(id: id(2), operation: .conditional(condition: expression,
                    ifTrue: empty, ifFalse: nil)), context: &context)
            case 5:
                let empty = try builder.addStatement(RTLResolvedStatement(id: id(1), operation: .empty), context: &context)
                _ = try builder.addCaseItem(matches: [expression], body: empty, context: &context)
            default:
                _ = try builder.addStatement(RTLResolvedStatement(id: id(1), operation: .block(children: 1..<2)), context: &context)
            }
            reject(builder, context: &context)
        }
    }

    @Test func clocksEdgesResetWidthsAndExplicitMixedProfilesAreRejected() throws {
        for mode in 0..<5 {
            var context = try context(); var builder = try builder(context: &context)
            let one = try LogicFourStateVector(repeating: .one, width: LogicBitWidth(1), context: &context)
            let wide = try LogicFourStateVector(repeating: .one, width: LogicBitWidth(8), context: &context)
            let clock = try builder.addExpression(id: id(1), type: type(1), operation: .constant(one), context: &context)
            let other = try builder.addExpression(id: id(2), type: type(1), operation: .constant(one), context: &context)
            let invalid = try builder.addExpression(id: id(3), type: type(8), operation: .constant(wide), context: &context)
            let body = try builder.addStatement(RTLResolvedStatement(id: id(1), operation: .empty), context: &context)
            let reset = mode == 4 ? RTLResolvedReset(signal: invalid, activeHigh: false) : nil
            try builder.addProcess(RTLResolvedProcess(id: id(1), control: .flipFlop(clock: mode == 0 ? invalid : clock,
                edge: .rising, asynchronousReset: reset), body: body), context: &context)
            if mode == 1 || mode == 2 {
                try builder.addProcess(RTLResolvedProcess(id: id(2), control: .flipFlop(clock: mode == 1 ? other : clock,
                    edge: mode == 2 ? .falling : .rising, asynchronousReset: nil), body: body), context: &context)
            } else if mode == 3 { try builder.addProcess(RTLResolvedProcess(id: id(2), control: .latch, body: body), context: &context) }
            reject(builder, context: &context)
        }
    }

    @Test func initialWidthsPortBindingsAndEntityIdentitiesAreChecked() throws {
        for mode in 0..<5 {
            var context = try context(); var builder = try builder(context: &context)
            let initial = mode == 0 ? try LogicFourStateVector(repeating: .unknown, width: LogicBitWidth(4), context: &context) : nil
            let signal = try builder.addSignal(RTLResolvedSignal(id: id(1), type: type(8), isInput: mode == 1,
                initialValue: initial), context: &context)
            if mode == 2 { _ = try builder.addSignal(RTLResolvedSignal(id: id(1), type: type(8)), context: &context) }
            if mode == 3 || mode == 4 {
                try builder.addPort(RTLResolvedPort(id: id(1), name: "q", direction: mode == 4 ? .input : .output, signal: signal), context: &context)
                if mode == 3 { try builder.addPort(RTLResolvedPort(id: id(2), name: "q", direction: .output, signal: signal), context: &context) }
            }
            reject(builder, context: &context)
        }
    }

    @Test func emptyTablesCancellationAndCapacityPreflightAreSafe() throws {
        let emptyCapacity = try RTLResolvedCapacity(signals: 0, expressions: 0, operands: 0, statements: 0,
            children: 0, caseItems: 0, caseMatches: 0, ports: 0, processes: 0)
        var context = try context(); let emptyBuilder = try ElaboratedRTLBuilder(topModuleID: id(1), capacity: emptyCapacity, context: &context)
        let design = try emptyBuilder.finish(context: &context)
        guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
        #expect(design.withExpressions { $0.isEmpty && $1.isEmpty && $2.isEmpty })
        #expect(design.withProgram { $0.isEmpty && $1.isEmpty && $2.isEmpty && $3.isEmpty && $4.isEmpty && $5.isEmpty && $6.isEmpty })
        var limited = try self.context(nodes: 1)
        do { _ = try builder(context: &limited); Issue.record("Node capacity bypassed limits") } catch { }
        #expect(limited.usage.peakManagedStorageBytes == 0)
        var cancelled = try self.context(control: Cancelled())
        let top = try id(1)
        do { _ = try ElaboratedRTLBuilder(topModuleID: top, capacity: emptyCapacity, context: &cancelled); Issue.record("Cancellation lost") } catch { #expect(error == .cancelled) }
    }

    @Test func dynamicSelectionRetainsSignedOffsetsWithoutInventingZeroBits() throws {
        for mode in 0..<3 {
            var context = try context(); var builder = try builder(context: &context)
            let value = try LogicFourStateVector(repeating: .one, width: LogicBitWidth(8), context: &context)
            let vector = try builder.addExpression(id: id(1), type: type(8), operation: .constant(value), context: &context)
            let offset = try builder.addExpression(id: id(2), type: WordLogicType(width: LogicBitWidth(8), isSigned: true),
                operation: .constant(value), context: &context)
            let result = try builder.addExpression(id: id(3), type: WordLogicType(width: LogicBitWidth(2), isSigned: mode == 1),
                operation: .dynamicSelect, inputs: mode == 2 ? [vector] : [vector, offset], context: &context)
            if mode == 0 {
                let design = try builder.finish(context: &context)
                guard #available(macOS 26.0, *) else { Issue.record("Requires macOS 26"); return }
                #expect(design.withExpressions { expressions, _, _ in
                    if case .dynamicSelect = expressions[result.rawValue].operation { return true }
                    return false
                })
            } else { reject(builder, context: &context) }
        }
    }
}
