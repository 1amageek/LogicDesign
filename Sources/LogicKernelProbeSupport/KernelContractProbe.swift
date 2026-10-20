import Synchronization
import LogicKernelCore
import LogicIR
import CircuiteFoundation
import SystemVerilogFrontend

@available(macOS 15.0, *)
public nonisolated func exerciseKernelContract() throws(LogicKernelError) {
    try exerciseExternalAccountingContract()
    let limits = try LogicKernelLimits(maximums: Dictionary(
        uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(100)) }
    ))
    let cancellation = LogicCancellationSource()
    let control: any LogicRunControlling = cancellation
    var context = LogicKernelContext(limits: limits, control: control)
    try context.charge(.workUnits, amount: 40)
    try context.charge(.workUnits, amount: 60)
    let first = try context.reserveStorage(byteCount: 40)
    let second = try context.reserveStorage(byteCount: 60)
    precondition(context.usage.peakManagedStorageBytes == 100)
    try context.releaseStorage(first)
    try context.releaseStorage(second)
    precondition(context.usage[.managedStorageBytes] == 0)
    do {
        try context.charge(.workUnits)
        preconditionFailure("Expected cumulative limit")
    } catch {
        precondition(error == .resourceLimit(resource: .workUnits, limit: 100, requested: 101))
    }
    cancellation.cancel()
    do {
        try context.checkpoint()
        preconditionFailure("Expected cancellation")
    } catch { precondition(error == .cancelled) }
}

@available(macOS 26.0, *)
public nonisolated func exerciseLogicValueContract() throws(LogicKernelError) {
    let vector = try LogicFourStateVector(
        width: LogicBitWidth(129), valueWords: [1, 0, 1], unknownWords: [0, .max, 0]
    )
    let highBit = try vector.bit(at: 128)
    let middleBit = try vector.bit(at: 64)
    precondition(highBit == .one)
    precondition(middleBit == .unknown)
    precondition(vector.withPlanes { values, unknowns in
        values.count == 3 && unknowns[1] == .max
    })
    precondition(LogicBit.zero.and(.unknown) == .zero)
    precondition(LogicBit.one.or(.highImpedance) == .one)
    precondition(LogicBit.unknown.xor(.unknown) == .unknown)
}

@available(macOS 26.0, *)
public nonisolated func exerciseBitGraphContract() throws {
    let limits = try LogicKernelLimits(maximums: Dictionary(
        uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(100_000)) }
    ))
    var context = LogicKernelContext(limits: limits, control: LogicCancellationSource())
    var builder = try BitLogicBuilder(capacity: BitGraphCapacity(nodes: 3, operands: 2,
        ports: 2, portBits: 3, states: 0), context: &context)
    let output = try builder.addNode(id: DesignEntityID(rawValue: 1), operation: .and,
                                    inputs: [BitNodeIndex(1), BitNodeIndex(2)], context: &context)
    let lhs = try builder.addNode(id: DesignEntityID(rawValue: 90), operation: .input, context: &context)
    let rhs = try builder.addNode(id: DesignEntityID(rawValue: 2), operation: .input, context: &context)
    try builder.addPort(id: DesignEntityID(rawValue: 1), direction: .input, bits: [lhs, rhs], context: &context)
    try builder.addPort(id: DesignEntityID(rawValue: 2), direction: .output, bits: [output], context: &context)
    let design = try builder.finish(context: &context)
    let valid = design.withTables { nodes, operands, _, _, _, order in
        guard order[2] == output else { return false }
        for pattern in 0..<4 {
            var values = [Bool](repeating: false, count: nodes.count)
            values[lhs.rawValue] = pattern & 1 != 0
            values[rhs.rawValue] = pattern & 2 != 0
            for position in order.indices {
                let index = order[position].rawValue
                let node = nodes[index]
                if node.operation == .and {
                    values[index] = values[operands[node.operands.lowerBound].rawValue]
                        && values[operands[node.operands.lowerBound + 1].rawValue]
                }
            }
            if values[output.rawValue] != (pattern == 3) { return false }
        }
        return true
    }
    precondition(valid)
    let emptyBuilder = try BitLogicBuilder(capacity: BitGraphCapacity(nodes: 0, operands: 0,
        ports: 0, portBits: 0, states: 0), context: &context)
    let empty = try emptyBuilder.finish(context: &context)
    precondition(empty.withTables { nodes, operands, ports, bits, states, order in
        nodes.isEmpty && operands.isEmpty && ports.isEmpty && bits.isEmpty && states.isEmpty && order.isEmpty
    })
    do throws(LogicKernelError) {
        try empty.withNodes { _ throws(LogicKernelError) -> Void in throw .cancelled }
        throw .invalidModel("Bit node callback did not propagate its typed failure")
    } catch { guard error == .cancelled else { throw error } }
    do throws(LogicKernelError) {
        try empty.withTables { _, _, _, _, _, _ throws(LogicKernelError) -> Void in throw .deadlineExceeded }
        throw .invalidModel("Bit table callback did not propagate its typed failure")
    } catch { guard error == .deadlineExceeded else { throw error } }
    var sequential = try BitLogicBuilder(capacity: BitGraphCapacity(nodes: 4, operands: 1,
        ports: 1, portBits: 1, states: 1), context: &context)
    let primary = try sequential.addNode(id: DesignEntityID(rawValue: 1), operation: .input, context: &context)
    let clock = try sequential.addNode(id: DesignEntityID(rawValue: 2), operation: .invert,
                                      inputs: [primary], context: &context)
    let data = try sequential.addNode(id: DesignEntityID(rawValue: 3), operation: .constant(true), context: &context)
    _ = try sequential.addNode(id: DesignEntityID(rawValue: 4), operation: .state(BitStateIndex(0)), context: &context)
    _ = try sequential.addState(BitLogicState(id: DesignEntityID(rawValue: 1), next: data,
        control: .flipFlop(clock: clock, edge: .rising, enable: nil, reset: nil)), context: &context)
    try sequential.addPort(id: DesignEntityID(rawValue: 1), direction: .input, bits: [primary], context: &context)
    let stateful = try sequential.finish(context: &context)
    precondition(stateful.withTables { _, _, _, _, states, _ in
        states.count == 1 && states[0].next == data && states[0].initialValue == nil
    })
    var invalid = try BitLogicBuilder(capacity: BitGraphCapacity(nodes: 1, operands: 1,
        ports: 0, portBits: 0, states: 0), context: &context)
    _ = try invalid.addNode(id: DesignEntityID(rawValue: 1), operation: .invert,
                           inputs: [BitNodeIndex(0)], context: &context)
    do {
        _ = try invalid.finish(context: &context)
        preconditionFailure("Cycle was accepted")
    } catch {
        precondition(error == .invalidModel("Combinational or transparent latch cycle"))
    }
}

@available(macOS 26.0, *)
public nonisolated func exerciseWordGraphContract() throws {
    let limits = try LogicKernelLimits(maximums: Dictionary(
        uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) }
    ))
    var context = LogicKernelContext(limits: limits, control: LogicCancellationSource())
    let wide = WordLogicType(width: try LogicBitWidth(129), isSigned: true)
    var builder = try WordLogicBuilder(capacity: WordGraphCapacity(nodes: 3, operands: 2,
        ports: 2, states: 0), context: &context)
    let sum = try builder.addNode(id: DesignEntityID(rawValue: 1), type: wide,
        operation: .compute(.add), inputs: [WordNodeIndex(1), WordNodeIndex(2)], context: &context)
    let input = try builder.addNode(id: DesignEntityID(rawValue: 90), type: wide,
        operation: .input, context: &context)
    let one = try LogicFourStateVector(width: wide.width, valueWords: [1, 0, 0], unknownWords: [0, 0, 0])
    _ = try builder.addNode(id: DesignEntityID(rawValue: 2), type: wide,
        operation: .constant(one), context: &context)
    try builder.addPort(WordLogicPort(id: DesignEntityID(rawValue: 1), direction: .input, value: input), context: &context)
    try builder.addPort(WordLogicPort(id: DesignEntityID(rawValue: 2), direction: .output, value: sum), context: &context)
    let design = try builder.finish(context: &context)
    precondition(design.withTables { nodes, operands, ports, states, order in
        nodes.count == 3 && nodes[sum.rawValue].type == wide && operands.count == 2
            && ports.count == 2 && states.isEmpty && order[2] == sum
    })
    do {
        try design.withNodes { _ throws(LogicKernelError) in throw .cancelled }
        preconditionFailure("Typed callback failure was lost")
    } catch { precondition(error == .cancelled) }
    let emptyBuilder = try WordLogicBuilder(capacity: WordGraphCapacity(nodes: 0, operands: 0,
        ports: 0, states: 0), context: &context)
    let empty = try emptyBuilder.finish(context: &context)
    precondition(empty.withTables { nodes, operands, ports, states, order in
        nodes.isEmpty && operands.isEmpty && ports.isEmpty && states.isEmpty && order.isEmpty
    })
    let unknown = try LogicFourStateVector(width: wide.width, valueWords: [0, 0, 0], unknownWords: [1, 0, 0])
    var invalid = try WordLogicBuilder(capacity: WordGraphCapacity(nodes: 1, operands: 0,
        ports: 0, states: 0), context: &context)
    _ = try invalid.addNode(id: DesignEntityID(rawValue: 1), type: wide, operation: .constant(unknown), context: &context)
    do {
        _ = try invalid.finish(context: &context)
        preconditionFailure("Unknown synthesis constant was accepted")
    } catch {
        guard case .invalidModel = error else { throw error }
    }
}

@available(macOS 26.0, *)
public nonisolated func exerciseSourceLexicalContract() throws {
    let limits = try LogicKernelLimits(maximums: Dictionary(
        uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) }
    ))
    var context = LogicKernelContext(limits: limits, control: LogicCancellationSource())
    let text = "/*日本*/ module top; endmodule"
    let artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
        hexadecimalValue: "a009b436ae3ecac5a7b12e02855ca1c389d442b177df51d784e3260e593033b8"), byteCount: 32)
    let document = try LogicSourceDocument(logicalName: "top.sv", artifactID: artifact,
        bytes: Array(text.utf8), context: &context)
    let bundle = try LogicSourceBundle(documents: [document], context: &context)
    precondition(bundle.withDocuments { $0.count == 1 && $0[0].byteCount == 32 })
    let lexer: any SystemVerilogTokenizing = SystemVerilogByteLexer()
    let stream = try lexer.tokenize(document, maximumTokens: 5, context: &context)
    precondition(stream.withTokens { tokens in
        tokens.count == 5 && tokens[0].byteRange == 11..<17
            && tokens[4].kind == .endOfFile && tokens[4].byteRange == 32..<32
    })
    do {
        _ = try lexer.tokenize(document, maximumTokens: 4, context: &context)
        preconditionFailure("Token capacity was ignored")
    } catch {
        guard case LogicKernelError.invalidInput = error else { throw error }
    }
}

@available(macOS 26.0, *)
public nonisolated func exerciseIntegerLiteralContract() throws {
    let limits = try LogicKernelLimits(maximums: Dictionary(
        uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) }
    ))
    var context = LogicKernelContext(limits: limits, control: LogicCancellationSource())
    let text = "129'sh100000000000000000000000000000000"
    let artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
        hexadecimalValue: "7c99909db5d496354ba2970439ba328217d7eefe8c8065bbf08cdaaf8cc1e1ad"), byteCount: 39)
    let document = try LogicSourceDocument(logicalName: "literal.sv", artifactID: artifact,
        bytes: Array(text.utf8), context: &context)
    let decoder: any SystemVerilogSynthesisLiteralDecoding = SystemVerilogSynthesisIntegerDecoder()
    let literal = try decoder.decode(0..<39, in: document, context: &context)
    guard case .integer(let value, let signed, let unsized) = literal else { preconditionFailure("Expected integer") }
    precondition(signed && !unsized && value.width.value == 129)
    let high = try value.bit(at: 128)
    precondition(high == .one && value.withPlanes { $0[0] == 0 && $0[1] == 0 && $0[2] == 1 && $1[2] == 0 })
}

@available(macOS 26.0, *)
public nonisolated func exerciseResolvedRTLContract() throws {
    let limits = try LogicKernelLimits(maximums: Dictionary(
        uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) }
    ))
    var context = LogicKernelContext(limits: limits, control: LogicCancellationSource())
    let top = try DesignEntityID(rawValue: 1024)
    var builder = try ElaboratedRTLBuilder(topModuleID: top, capacity: RTLResolvedCapacity(signals: 2,
        expressions: 5, operands: 2, statements: 3, children: 0, caseItems: 2, caseMatches: 2,
        ports: 2, processes: 1), context: &context)
    let boolean = WordLogicType(width: try LogicBitWidth(1))
    let wide = WordLogicType(width: try LogicBitWidth(129))
    let clock = try builder.addSignal(RTLResolvedSignal(id: DesignEntityID(rawValue: 1), type: boolean, isInput: true), context: &context)
    let state = try builder.addSignal(RTLResolvedSignal(id: DesignEntityID(rawValue: 2), type: wide), context: &context)
    let clockRead = try builder.addExpression(id: DesignEntityID(rawValue: 1), type: boolean, operation: .read(clock), context: &context)
    let zeroValue = try LogicFourStateVector(repeating: .zero, width: boolean.width, context: &context)
    let oneValue = try LogicFourStateVector(repeating: .one, width: boolean.width, context: &context)
    let zero = try builder.addExpression(id: DesignEntityID(rawValue: 2), type: boolean, operation: .constant(zeroValue), context: &context)
    let one = try builder.addExpression(id: DesignEntityID(rawValue: 3), type: boolean, operation: .constant(oneValue), context: &context)
    let constant = try LogicFourStateVector(width: wide.width, valueWords: [1, 0, 0], unknownWords: [0, 0, 0])
    let data = try builder.addExpression(id: DesignEntityID(rawValue: 4), type: wide, operation: .constant(constant), context: &context)
    let selection = try builder.addExpression(id: DesignEntityID(rawValue: 5), type: boolean, operation: .dynamicSelect,
        inputs: [data, zero], context: &context)
    let assignment = try builder.addStatement(RTLResolvedStatement(id: DesignEntityID(rawValue: 1), operation: .assignment(
        target: state, selection: 0..<129, value: data, timing: .nonBlocking)), context: &context)
    let empty = try builder.addStatement(RTLResolvedStatement(id: DesignEntityID(rawValue: 2), operation: .empty), context: &context)
    _ = try builder.addCaseItem(matches: [zero], body: empty, context: &context)
    _ = try builder.addCaseItem(matches: [one], body: assignment, context: &context)
    let body = try builder.addStatement(RTLResolvedStatement(id: DesignEntityID(rawValue: 3), operation: .caseStatement(
        selector: selection, items: 0..<2, defaultBody: empty)), context: &context)
    try builder.addProcess(RTLResolvedProcess(id: DesignEntityID(rawValue: 1), control: .flipFlop(clock: clockRead,
        edge: .rising, asynchronousReset: nil), body: body), context: &context)
    try builder.addPort(RTLResolvedPort(id: DesignEntityID(rawValue: 1), name: "clock", direction: .input, signal: clock), context: &context)
    try builder.addPort(RTLResolvedPort(id: DesignEntityID(rawValue: 2), name: "q", direction: .output, signal: state), context: &context)
    let design = try builder.finish(context: &context)
    precondition(design.topModuleID == top)
    precondition(design.withProgram { signals, statements, children, items, matches, ports, processes in
        guard case .assignment(_, _, _, .nonBlocking) = statements[0].operation else { return false }
        return signals[1].initialValue == nil && children.isEmpty && items[1].body == assignment
            && matches[0] == zero && ports.count == 2 && processes[0].body == body
    })
    let emptyBuilder = try ElaboratedRTLBuilder(topModuleID: top, capacity: RTLResolvedCapacity(signals: 0,
        expressions: 0, operands: 0, statements: 0, children: 0, caseItems: 0, caseMatches: 0,
        ports: 0, processes: 0), context: &context)
    let emptyDesign = try emptyBuilder.finish(context: &context)
    precondition(emptyDesign.withExpressions { $0.isEmpty && $1.isEmpty && $2.isEmpty })
    precondition(emptyDesign.withProgram { $0.isEmpty && $1.isEmpty && $2.isEmpty && $3.isEmpty && $4.isEmpty && $5.isEmpty && $6.isEmpty })
}

@available(macOS 26.0, *)
public nonisolated func exercisePortableSyntaxContract() throws {
    let limits = try LogicKernelLimits(maximums: Dictionary(
        uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) }
    ))
    var context = LogicKernelContext(limits: limits, control: LogicCancellationSource())
    let text = "module top #(parameter W=129)(input clk, reset_n, input [W-1:0] a, output logic [W-1:0] q); always_ff @(negedge reset_n or posedge clk) if (!reset_n) q <= 129'h0; else q <= {a[W-1:1], a[0]}; for (genvar i=0; i<W; i++) begin : g wire b; assign b = a[i]; end endmodule"
    let artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
        hexadecimalValue: "3f9374c9ae92a524d7878423800fe8abe2d32ff8945cbbf0ea752264df2fe2e1"), byteCount: 266)
    let source = try LogicSourceDocument(logicalName: "syntax.sv", artifactID: artifact,
        bytes: Array(text.utf8), context: &context)
    let tokens = try SystemVerilogByteLexer().tokenize(source, maximumTokens: 200, context: &context)
    let syntaxLimits = try SystemVerilogSyntaxLimits(nodes: 200, children: 200, symbols: 30, nesting: 40)
    // The hash key remains UInt64 even when target indices are 32-bit Int values.
    let publishedBytes = UInt64(syntaxLimits.nodes * MemoryLayout<SystemVerilogSyntaxNode>.stride
        + syntaxLimits.children * MemoryLayout<Int>.stride + syntaxLimits.symbols * MemoryLayout<Range<Int>>.stride)
    let scratchBytes = UInt64(syntaxLimits.children * 2 * MemoryLayout<Int>.stride
        + syntaxLimits.symbols * (2 * MemoryLayout<Int>.stride + MemoryLayout<UInt64>.stride))
    let expectedBytes = publishedBytes + scratchBytes
    var accounting = LogicKernelContext(limits: limits, control: LogicCancellationSource())
    _ = try SystemVerilogSyntaxParser.parse(tokens, limits: syntaxLimits, context: &accounting)
    precondition(accounting.usage.peakManagedStorageBytes == expectedBytes, "Syntax payload accounting differs from target layout")
    let tightLimits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
        LogicResource.allCases.map { ($0, $0 == .managedStorageBytes ? expectedBytes - 1 : UInt64(1_000_000)) }))
    var tight = LogicKernelContext(limits: tightLimits, control: LogicCancellationSource())
    do {
        _ = try SystemVerilogSyntaxParser.parse(tokens, limits: syntaxLimits, context: &tight)
        preconditionFailure("Syntax allocation exceeded the admitted storage budget")
    } catch {
        guard case .resourceLimit(.managedStorageBytes, expectedBytes - 1, expectedBytes) = error else { throw error }
        precondition(tight.usage[.allocationBytes] == 0 && tight.usage[.managedStorageBytes] == 0)
    }
    let tree = try SystemVerilogSyntaxParser.parse(tokens, limits: syntaxLimits, context: &context)
    var events = 0; var firstFalling = false; var nonblocking = 0; var generated = 0
    let valid = tree.withTables { nodes, children, symbols in
        guard tree.modules.count == 1, !symbols.isEmpty,
              case .module = nodes[children[tree.modules.lowerBound]].kind else { return false }
        for index in nodes.indices {
            switch nodes[index].kind {
            case .event(let edge, _):
                if events == 0 { firstFalling = edge == .falling }
                events += 1
            case .assignment(.nonBlocking, _, _): nonblocking += 1
            case .generateFor: generated += 1
            default: break
            }
        }
        return true
    }
    precondition(valid && firstFalling && events == 2 && nonblocking == 2 && generated == 1)
    do {
        _ = try SystemVerilogSyntaxParser.parse(tokens, limits: SystemVerilogSyntaxLimits(
            nodes: 200, children: 200, symbols: 30, nesting: 1), context: &context)
        preconditionFailure("Syntax nesting capacity was ignored")
    } catch {
        guard case .sourceFailure(let code, let range, _) = error else { throw error }
        precondition(code.rawValue == "SV_SYNTAX_NESTING_LIMIT" && range.artifactID == artifact)
    }
    for (text, digest, expectedCode, expectedRange) in [
        ("module t; assign q=$time; endmodule", "29948403e6504cfde7e7355e10e887dfdc0ff5708c1b7e88012234b4f4bacf69",
         "SV_SYNTAX_SYSTEM_IDENTIFIER", 19..<24),
        ("module t; endmodule : wrong", "1960f42901987f1d4164a835dc717b4316306015d4b576590d50c091acd80605",
         "SV_SYNTAX_END_LABEL", 22..<27)
    ] {
        let rejectedArtifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256, hexadecimalValue: digest),
            byteCount: UInt64(text.utf8.count))
        let rejectedSource = try LogicSourceDocument(logicalName: "rejected.sv", artifactID: rejectedArtifact,
            bytes: Array(text.utf8), context: &context)
        let rejectedTokens = try SystemVerilogByteLexer().tokenize(rejectedSource, maximumTokens: 30, context: &context)
        do {
            _ = try SystemVerilogSyntaxParser.parse(rejectedTokens, limits: syntaxLimits, context: &context)
            preconditionFailure("Invalid syntax was accepted")
        } catch {
            guard case .sourceFailure(let code, let range, _) = error else { throw error }
            precondition(code.rawValue == expectedCode && range.artifactID == rejectedArtifact
                && range.byteRange == UInt64(expectedRange.lowerBound)..<UInt64(expectedRange.upperBound))
        }
    }
}

@available(macOS 26.0, *)
public nonisolated func exerciseBinaryValueContract() throws(LogicKernelError) {
    let limits = try LogicKernelLimits(maximums: Dictionary(
        uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) }
    ))
    var context = LogicKernelContext(limits: limits, control: LogicCancellationSource())
    let width = try LogicBitWidth(129)
    let ones = try LogicFourStateVector(width: width, valueWords: [.max, .max, 1], unknownWords: [0, 0, 0])
    let zero = try LogicFourStateVector(repeating: .zero, width: width, context: &context)
    let one = try LogicFourStateVector(width: width, valueWords: [1, 0, 0], unknownWords: [0, 0, 0])
    let sum = try ones.addingBinary(one, context: &context)
    let difference = try zero.subtractingBinary(one, context: &context)
    let product = try ones.multiplyingBinary(ones, context: &context)
    precondition(sum == zero && difference == ones && product == one)
    let nativeWidth = try LogicBitWidth(Int.bitWidth)
    let nativeMinimum = try LogicFourStateVector(width: nativeWidth,
        valueWords: [UInt64(truncatingIfNeeded: Int.min) & nativeWidth.tailMask], unknownWords: [0])
    let extended = try nativeMinimum.resizedBinary(to: width, signExtend: true, context: &context)
    let index = try extended.binaryInt(signed: true, context: &context)
    precondition(index == Int.min)
    let huge = try LogicFourStateVector(width: width, valueWords: [0, 0, 1], unknownWords: [0, 0, 0])
    let overshift = try ones.shiftingBinary(left: true, amount: huge, context: &context)
    let arithmetic = try ones.shiftingBinary(left: false, amount: huge, arithmetic: true, context: &context)
    precondition(overshift == zero && arithmetic == ones)
    let lower = try one.slicingBinary(offset: 0, width: LogicBitWidth(1), context: &context)
    let joined = try one.concatenatingBinary(lower, context: &context)
    precondition(joined.width.value == 130 && joined.withPlanes { words, unknowns in
        words[0] == 3 && words[1] == 0 && words[2] == 0 && unknowns[2] == 0
    })
    let unknown = try LogicFourStateVector(repeating: .unknown, width: width, context: &context)
    do {
        _ = try unknown.addingBinary(one, context: &context)
        preconditionFailure("Binary arithmetic accepted X")
    } catch {
        guard case .invalidModel = error else { throw error }
    }
}

@available(macOS 26.0, *)
public nonisolated func exerciseParameterBindingContract() throws {
    let limits = try LogicKernelLimits(maximums: Dictionary(
        uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000)) }
    ))
    var context = LogicKernelContext(limits: limits, control: LogicCancellationSource())
    let text = "module first #(parameter W=129, D=W+1); localparam [W-1:0] MASK='1; endmodule module second #(parameter W=8, D=W+1); endmodule module empty; endmodule"
    let artifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256,
        hexadecimalValue: "ec6bfec5e6a56c578aa800cce90ab19918a8c8baad7632940a21335abfd0a67d"), byteCount: 150)
    let source = try LogicSourceDocument(logicalName: "parameters.sv", artifactID: artifact,
        bytes: Array(text.utf8), context: &context)
    let tokens = try SystemVerilogByteLexer().tokenize(source, maximumTokens: 100, context: &context)
    let tree = try SystemVerilogSyntaxParser.parse(tokens, limits: SystemVerilogSyntaxLimits(
        nodes: 100, children: 100, symbols: 20, nesting: 30), context: &context)
    let firstModule = try tree.child(at: tree.modules.lowerBound)
    let first = try SystemVerilogParameterBinder.bind(tree, module: firstModule, context: &context)
    let second = try SystemVerilogParameterBinder.bind(tree,
        module: tree.child(at: tree.modules.lowerBound + 1), context: &context)
    let empty = try SystemVerilogParameterBinder.bind(tree,
        module: tree.child(at: tree.modules.lowerBound + 2), context: &context)
    let firstW = try first.declaration(at: 0); let secondW = try second.declaration(at: 0)
    precondition(first.count == 3 && second.count == 2 && firstW != secondW)
    let valid = first.withBindings { declarations, references, _ in
        guard declarations.count == 3 else { return false }
        var count = 0
        for index in references.indices { if references[index] == firstW { count += 1 } }
        return count == 2
    }
    precondition(valid && empty.withBindings { $0.isEmpty && $1.count == tree.nodeCount && $2.count == tree.symbolCount })
    let published = UInt64((2 * tree.nodeCount + tree.symbolCount) * MemoryLayout<Int>.stride)
    let scratch = UInt64(tree.nodeCount * (MemoryLayout<Int>.stride + MemoryLayout<UInt8>.stride))
    let exactLimits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
        LogicResource.allCases.map { ($0, $0 == .managedStorageBytes ? published + scratch : UInt64(1_000_000)) }))
    var exact = LogicKernelContext(limits: exactLimits, control: LogicCancellationSource())
    _ = try SystemVerilogParameterBinder.bind(tree, module: firstModule, context: &exact)
    precondition(exact.usage.peakManagedStorageBytes == published + scratch && exact.usage[.managedStorageBytes] == published)
    let tightLimits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues:
        LogicResource.allCases.map { ($0, $0 == .managedStorageBytes ? published + scratch - 1 : UInt64(1_000_000)) }))
    var tight = LogicKernelContext(limits: tightLimits, control: LogicCancellationSource())
    do {
        _ = try SystemVerilogParameterBinder.bind(tree, module: firstModule, context: &tight)
        preconditionFailure("Parameter tables exceeded storage admission")
    } catch {
        guard case .resourceLimit(.managedStorageBytes, _, _) = error else { throw error }
        precondition(tight.usage[.allocationBytes] == 0)
    }
    for (text, digest, code, end) in [
        ("module m; parameter A=B, B=1; endmodule", "b6a92f8ec4adbdfc95f1852a3d801e5e9c7c22ab252f7f11eb88ab206172e07d",
         "SV_PARAMETER_BEFORE_DECLARATION", 23),
        ("module m; parameter A=A; endmodule", "cf77e2b4eaefebccbf4ce47eb38ecd27f611a63b9ee319e0da528df7e843ce1f",
         "SV_PARAMETER_SELF_REFERENCE", 23),
        ("module m; parameter A=NO_NAME; endmodule", "ed3c1ea6e6934e48710edb0b8a05fc4fd842c0e14fce720d4c30f065d0ce0e71",
         "SV_PARAMETER_UNRESOLVED_NAME", 29)
    ] {
        let rejectedArtifact = try ArtifactID(digest: ContentDigest(algorithm: .sha256, hexadecimalValue: digest),
            byteCount: UInt64(text.utf8.count))
        let rejected = try LogicSourceDocument(logicalName: "invalid-parameter.sv", artifactID: rejectedArtifact,
            bytes: Array(text.utf8), context: &context)
        let rejectedTokens = try SystemVerilogByteLexer().tokenize(rejected, maximumTokens: 30, context: &context)
        let syntax = try SystemVerilogSyntaxParser.parse(rejectedTokens, limits: SystemVerilogSyntaxLimits(
            nodes: 100, children: 100, symbols: 20, nesting: 30), context: &context)
        do {
            _ = try SystemVerilogParameterBinder.bind(syntax, module: syntax.child(at: syntax.modules.lowerBound), context: &context)
            preconditionFailure("Invalid parameter dependency was accepted")
        } catch {
            guard case .sourceFailure(let actual, let range, _) = error else { throw error }
            precondition(actual.rawValue == code && range.artifactID == rejectedArtifact && range.byteRange == 22..<UInt64(end))
        }
    }
}

// The exact same owners and protocol requirements execute on Native and both WASM modes.
@available(macOS 15.0, *)
private final class ProbeKernelAccountant: LogicKernelAccounting {
    struct State: Sendable { var live: UInt64 = 0; var allocations: UInt64 = 0; var work: UInt64 = 0; var refuse = false; var released: [UInt64] = [] }
    let state = Mutex(State())
    func observeBitWidth(_ width: UInt64) throws(LogicKernelError) {
        if state.withLock({ $0.refuse }) { throw .externalAccountingFailure }
    }
    func charge(_ resource: LogicResource, amount: UInt64) throws(LogicKernelError) {
        let refused = state.withLock { state in
            if state.refuse { return true }
            state.work += amount; return false
        }
        if refused { throw .externalAccountingFailure }
    }
    func reserveStorage(byteCount: UInt64) throws(LogicKernelError) -> any LogicKernelStorageRetaining {
        let refused = state.withLock { state in
            if state.refuse { return true }
            state.live += byteCount; state.allocations += byteCount; return false
        }
        if refused { throw .externalAccountingFailure }
        return Lease(owner: self, bytes: byteCount)
    }
    private final class Lease: LogicKernelStorageRetaining {
        let owner: ProbeKernelAccountant; let bytes: UInt64
        init(owner: ProbeKernelAccountant, bytes: UInt64) { self.owner = owner; self.bytes = bytes }
        deinit { owner.state.withLock { $0.live -= bytes; $0.released.append(bytes) } }
    }
}
@available(macOS 15.0, *)
private nonisolated func exerciseExternalAccountingContract() throws(LogicKernelError) {
    let limits = try LogicKernelLimits(maximums: Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(100_000)) }))
    // These event assertions execute unchanged on Native, WASM and Embedded.
    let registryOwner = ProbeKernelAccountant()
    do {
        var context = LogicKernelContext(limits: limits, control: LogicCancellationSource(), accounting: registryOwner)
        _ = try context.reserveStorage(byteCount: 71)
    }
    precondition(registryOwner.state.withLock {
        $0.live == 0 && $0.released.count == 3 && $0.released.first == 71
    })
    var registryContext = LogicKernelContext(limits: limits, control: LogicCancellationSource(), accounting: registryOwner)
    for _ in 0..<8 {
        let zero = try registryContext.reserveStorage(byteCount: 0)
        let minimumBuckets = 2 * (MemoryLayout<(UInt64, UInt64)>.stride
            + MemoryLayout<UInt64>.stride
            + MemoryLayout<(UInt64, any LogicKernelStorageRetaining)>.stride)
        precondition(registryOwner.state.withLock { $0.live >= UInt64(minimumBuckets) })
        try registryContext.releaseStorage(zero)
        precondition(registryOwner.state.withLock { $0.live == 0 })
    }
    let retainedScope = try registryContext.beginRetentionScope()
    _ = try registryContext.reserveStorage(byteCount: 71)
    var retained: LogicKernelRetention? = try registryContext.finishRetentionScope(retainedScope)
    var retainedCopy = retained
    retained = nil
    let anchorBytes = UInt64(2 * MemoryLayout<UInt>.stride
        + MemoryLayout<[UInt64: UInt64]>.stride
        + MemoryLayout<(any LogicKernelStorageRetaining)?>.stride)
    let tableBytes = registryOwner.state.withLock { $0.live } - 71 - anchorBytes
    registryOwner.state.withLock { $0.released = [] }
    withExtendedLifetime(retainedCopy) { precondition(registryOwner.state.withLock { $0.live > 0 }) }
    retainedCopy = nil
    precondition(registryOwner.state.withLock {
        $0.live == 0 && $0.released.count == 3 && $0.released.last == tableBytes
            && $0.released.dropLast().contains(71)
    })
    let a = LogicCancellationSource(); let owner = ProbeKernelAccountant()
    var context = LogicKernelContext(limits: limits, control: a, accounting: owner)
    try context.requireAccounting(expected: owner)
    let failed = try context.beginRetentionScope()
    _ = try context.reserveStorage(byteCount: 24)
    let administrativeWork = context.usage[.workUnits]
    try context.charge(.workUnits, amount: 3)
    a.cancel()
    try context.discardRetentionScope(failed)
    precondition(owner.state.withLock { $0.live == 0 && $0.work == administrativeWork + 3 })
    let fresh = LogicCancellationSource()
    var resultContext = LogicKernelContext(limits: limits, control: fresh, accounting: owner)
    let scope = try resultContext.beginRetentionScope()
    _ = try resultContext.reserveStorage(byteCount: 48)
    var first: LogicKernelRetention? = try resultContext.finishRetentionScope(scope)
    var second = first
    first = nil
    withExtendedLifetime(second) { precondition(owner.state.withLock { $0.live > 0 }) }
    second = nil
    precondition(owner.state.withLock { $0.live == 0 })
    let failureControl = LogicCancellationSource()
    var failureContext = LogicKernelContext(limits: limits, control: failureControl, accounting: owner)
    let failedScope = try failureContext.beginRetentionScope()
    _ = try failureContext.reserveStorage(byteCount: 19)
    owner.state.withLock { $0.refuse = true }
    failureControl.cancel()
    var failureRetention: LogicKernelRetention? = try failureContext.retainFailureScope(failedScope)
    withExtendedLifetime(failureRetention) { precondition(owner.state.withLock { $0.live > 0 }) }
    failureRetention = nil
    precondition(owner.state.withLock { $0.live == 0 })
    let beforeImportWork = failureContext.usage[.workUnits]
    try failureContext.importAccountedPhase(peakStorageBytes: 4, allocationBytes: 8,
        storageReservations: 1, workUnits: 2, expectedAccounting: owner)
    precondition(failureContext.usage[.workUnits] == beforeImportWork + 2)
    let before = resultContext.usage
    do { try resultContext.charge(.nodes); preconditionFailure("Expected external refusal") }
    catch { precondition(error == .externalAccountingFailure) }
    precondition(resultContext.usage == before)
}
