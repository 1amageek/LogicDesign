import LogicIR
import LogicKernelCore

// Test-only binary program oracle. It executes emitted RTL and samples NBA values
// during Active, then iterates combinational processes to a fixed point. Initial
// zeros are explicit fixture inputs, not production simulation initialization.
@available(macOS 26.0, *)
package struct ProbeRTLProgramEvaluator {
    typealias Write = (signal: Int, range: Range<Int>, value: LogicFourStateVector)

    package static func evaluate(_ model: borrowing ElaboratedRTL, inputs: [String: Int],
        context: inout LogicKernelContext) throws(LogicKernelError) -> [String: Int] {
        var values: [LogicFourStateVector] = []
        try model.withProgram { (signals,_,_,_,_,ports,_) throws(LogicKernelError) in
            for index in 0..<signals.count {
                values.append(try number(0, width: signals[index].type.width, context: &context))
            }
            for index in 0..<ports.count where ports[index].direction == .input {
                let port = ports[index]
                guard let input = inputs[port.name] else { throw .invalidInput("Missing binary fixture input") }
                values[port.signal.rawValue] = try number(UInt64(truncatingIfNeeded: input), width: signals[port.signal.rawValue].type.width, context: &context)
            }
        }
        var stable = false
        for _ in 0..<30 {
            let previous = values
            var pending: [Write] = []
            try model.withProgram { (_,_,_,_,_,_,processes) throws(LogicKernelError) in
                for index in 0..<processes.count {
                    switch processes[index].control {
                    case .continuous, .combinational, .levelSensitive: break
                    case .flipFlop, .latch: throw .invalidInput("This fixture oracle is combinational")
                    }
                    try execute(processes[index].body, model: model, values: &values, pending: &pending, context: &context)
                }
            }
            for write in pending { try apply(write, values: &values, context: &context) }
            if previous == values { stable = true; break }
        }
        guard stable else { throw .invalidModel("Binary fixture did not stabilize") }
        return try model.withProgram { (_,_,_,_,_,ports,_) throws(LogicKernelError) in
            var result: [String: Int] = [:]
            for index in 0..<ports.count where ports[index].direction == .output {
                result[ports[index].name] = try values[ports[index].signal.rawValue].binaryInt(signed: false, context: &context)
            }
            return result
        }
    }
    static func execute(_ index: RTLStatementIndex, model: borrowing ElaboratedRTL,
        values: inout [LogicFourStateVector], pending: inout [Write], context: inout LogicKernelContext)
        throws(LogicKernelError) {
        try context.charge(.workUnits)
        try model.withProgram { (_,statements,children,items,matches,_,_) throws(LogicKernelError) in
            switch statements[index.rawValue].operation {
            case .empty: break
            case .assignment(let signal,let range,let rhs,let timing):
                let value = try ProbeRTLExpressionEvaluator.evaluate(model, signals: values, result: rhs, context: &context)
                let write = (signal.rawValue,range,value)
                switch timing {
                case .blocking: try apply(write, values: &values, context: &context)
                case .nonBlocking: pending.append(write)
                }
            case .assignmentGroup(let body):
                var sampled: [(Write, RTLResolvedStatement.Timing)] = []
                for offset in body {
                    try sample(children[offset], model: model, values: values, sampled: &sampled, context: &context)
                }
                for (write, timing) in sampled {
                    switch timing {
                    case .blocking: try apply(write, values: &values, context: &context)
                    case .nonBlocking: pending.append(write)
                    }
                }
            case .block(let body):
                for offset in body { try execute(children[offset], model: model, values: &values, pending: &pending, context: &context) }
            case .conditional(let condition,let yes,let no):
                let test = try ProbeRTLExpressionEvaluator.evaluate(model, signals: values, result: condition, context: &context)
                if try test.reducingBinary(.or, context: &context) { try execute(yes, model: model, values: &values, pending: &pending, context: &context) }
                else if let no { try execute(no, model: model, values: &values, pending: &pending, context: &context) }
            case .caseStatement(let selector,let arms,let fallback):
                let value = try ProbeRTLExpressionEvaluator.evaluate(model, signals: values, result: selector, context: &context)
                var selected: RTLStatementIndex?
                for arm in arms {
                    for match in items[arm].matches {
                        let candidate = try ProbeRTLExpressionEvaluator.evaluate(model, signals: values, result: matches[match], context: &context)
                        if selected == nil, value == candidate { selected = items[arm].body }
                    }
                }
                if let selected = selected ?? fallback { try execute(selected, model: model, values: &values, pending: &pending, context: &context) }
            }
        }
    }
    static func sample(_ index: RTLStatementIndex, model: borrowing ElaboratedRTL,
        values: borrowing [LogicFourStateVector], sampled: inout [(Write, RTLResolvedStatement.Timing)],
        context: inout LogicKernelContext) throws(LogicKernelError) {
        try model.withProgram { (_,statements,children,_,_,_,_) throws(LogicKernelError) in
            switch statements[index.rawValue].operation {
            case .assignment(let signal,let range,let rhs,let timing):
                let value = try ProbeRTLExpressionEvaluator.evaluate(model, signals: values, result: rhs, context: &context)
                sampled.append(((signal.rawValue,range,value),timing))
            case .conditional(let condition,let yes,let no):
                let value = try ProbeRTLExpressionEvaluator.evaluate(model, signals: values, result: condition, context: &context)
                if try value.reducingBinary(.or, context: &context) { try sample(yes, model: model, values: values, sampled: &sampled, context: &context) }
                else if let no { try sample(no, model: model, values: values, sampled: &sampled, context: &context) }
            case .assignmentGroup(let body):
                for offset in body { try sample(children[offset], model: model, values: values, sampled: &sampled, context: &context) }
            case .empty: break
            case .block, .caseStatement: throw .invalidModel("Invalid fixture assignment group")
            }
        }
    }
    static func apply(_ write: Write, values: inout [LogicFourStateVector], context: inout LogicKernelContext)
        throws(LogicKernelError) {
        let type = values[write.signal].width
        guard type.value < 63 else { throw .invalidInput("Fixture integer oracle is limited to 62 bits") }
        let previous = try UInt64(values[write.signal].binaryInt(signed: false, context: &context))
        let value = try UInt64(write.value.binaryInt(signed: false, context: &context))
        let mask = ((UInt64(1) << write.range.count)-1) << write.range.lowerBound
        values[write.signal] = try number((previous & ~mask) | ((value << write.range.lowerBound) & mask), width: type, context: &context)
    }
    static func number(_ value: UInt64, width: LogicBitWidth, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicFourStateVector {
        guard width.value < 63 else { throw .invalidInput("Fixture integer oracle is limited to 62 bits") }
        _ = try context.reserveStorage(byteCount: 16)
        return try LogicFourStateVector(width: width, valueWords: [value & width.tailMask], unknownWords: [0])
    }
}
