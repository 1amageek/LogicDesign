import Foundation
import LogicIR
import XcircuitePackage

public struct SystemVerilogParser: SystemVerilogParsing {
    private let lexer: SystemVerilogLexing

    public init(lexer: SystemVerilogLexing = SystemVerilogLexer()) {
        self.lexer = lexer
    }

    public func parse(_ sources: [SystemVerilogSourceUnit], topDesignName: String) -> SystemVerilogParseResult {
        parse(sources, topDesignName: topDesignName, allowResolvedIncludes: false)
    }

    public func parseResolvedIncludes(
        _ sources: [SystemVerilogSourceUnit],
        topDesignName: String
    ) -> SystemVerilogParseResult {
        parse(sources, topDesignName: topDesignName, allowResolvedIncludes: true)
    }

    private func parse(
        _ sources: [SystemVerilogSourceUnit],
        topDesignName: String,
        allowResolvedIncludes: Bool
    ) -> SystemVerilogParseResult {
        var modules: [RTLModule] = []
        var sourceFiles: [LogicSourceFile] = []
        var diagnostics: [LogicDiagnostic] = []
        var unsupported = false
        var macroValues: [String: Int64] = [:]
        var macroDefinitions: [String: ParserState.MacroDefinition] = [:]

        for source in sources {
            sourceFiles.append(source.file)
            let lexResult = lexer.lex(source)
            diagnostics.append(contentsOf: lexResult.diagnostics)
            var state = ParserState(
                tokens: lexResult.tokens,
                sourcePath: source.path,
                macroValues: macroValues,
                macroDefinitions: macroDefinitions,
                allowResolvedIncludes: allowResolvedIncludes
            )
            while !state.isAtEnd {
                if state.current.lexeme == "`" {
                    state.parseCompilerDirective()
                } else if !state.isPreprocessorActive {
                    _ = state.advance()
                } else if state.match("module") {
                    if let module = state.parseModule() {
                        modules.append(module)
                    }
                } else {
                    let token = state.current
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "SV_PARSE_EXPECTED_MODULE",
                        message: "Only module declarations and supported compiler directives are allowed at the source root.",
                        entity: token.lexeme,
                        location: token.span,
                        suggestedActions: ["move_declaration_into_module", "remove_unsupported_directive"]
                    ))
                    state.skipUntilSemicolon()
                }
                diagnostics.append(contentsOf: state.diagnostics)
                unsupported = unsupported || state.unsupportedSemantics
                macroValues = state.macroValues
                macroDefinitions = state.macroDefinitions
                state.diagnostics.removeAll()
            }
            state.finalizePreprocessor()
            diagnostics.append(contentsOf: state.diagnostics)
            unsupported = unsupported || state.unsupportedSemantics
            macroDefinitions = state.macroDefinitions
        }

        let design = modules.isEmpty ? nil : RTLDesign(
            topModuleName: topDesignName,
            modules: modules,
            sourceFiles: sourceFiles
        )
        return SystemVerilogParseResult(
            design: design,
            diagnostics: diagnostics,
            unsupportedSemantics: unsupported
        )
    }

    private struct ParserState {
        struct MacroDefinition {
            var isFunctionLike: Bool
            var parameters: [String]
            var replacement: [SystemVerilogToken]
        }

        var tokens: [SystemVerilogToken]
        var index: Int = 0
        var sourcePath: String
        var moduleNameForIDs: String = ""
        var parameterValues: [String: Int64] = [:]
        var macroValues: [String: Int64]
        var macroDefinitions: [String: MacroDefinition]
        var allowResolvedIncludes: Bool
        var expandingMacros: Set<String> = []
        private var conditionalFrames: [ConditionalFrame] = []
        var diagnostics: [LogicDiagnostic] = []
        var unsupportedSemantics = false

        private struct ConditionalFrame {
            var parentActive: Bool
            var branchTaken: Bool
            var branchActive: Bool
            var elseSeen: Bool
        }

        init(
            tokens: [SystemVerilogToken],
            sourcePath: String,
            macroValues: [String: Int64] = [:],
            macroDefinitions: [String: MacroDefinition] = [:],
            allowResolvedIncludes: Bool = false
        ) {
            self.tokens = tokens
            self.sourcePath = sourcePath
            self.macroValues = macroValues
            self.macroDefinitions = macroDefinitions
            self.allowResolvedIncludes = allowResolvedIncludes
        }

        var current: SystemVerilogToken { tokens[min(index, tokens.count - 1)] }
        var previous: SystemVerilogToken { tokens[max(0, index - 1)] }
        var isAtEnd: Bool { current.kind == .endOfFile }
        var isPreprocessorActive: Bool {
            conditionalFrames.allSatisfy(\.branchActive)
        }

        mutating func advance() -> SystemVerilogToken {
            let token = current
            if !isAtEnd { index += 1 }
            return token
        }

        mutating func match(_ lexeme: String) -> Bool {
            guard current.lexeme == lexeme else { return false }
            _ = advance()
            return true
        }

        mutating func expect(_ lexeme: String, code: String = "SV_PARSE_EXPECTED_TOKEN") -> Bool {
            guard match(lexeme) else {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: code,
                    message: "Expected '\(lexeme)' but found '\(current.lexeme)'.",
                    entity: current.lexeme,
                    location: current.span,
                    suggestedActions: ["correct_syntax"]
                ))
                return false
            }
            return true
        }

        mutating func parseModule() -> RTLModule? {
            guard let name = consumeIdentifier() else {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "SV_PARSE_MODULE_NAME_MISSING",
                    message: "A module declaration requires a name.",
                    location: current.span,
                    suggestedActions: ["add_module_name"]
                ))
                skipUntilSemicolon()
                return nil
            }
            moduleNameForIDs = name
            parameterValues.removeAll()
            let start = previous.span.start
            var parameters: [RTLParameter] = []
            if match("#") {
                _ = expect("(")
                parameters = parseParameterDeclarations(until: ")")
                _ = expect(")")
            }

            var ports: [RTLPort] = []
            if match("(") {
                ports = parsePortHeader()
                _ = expect(")")
            }
            _ = expect(";")

            var signals: [RTLSignal] = []
            var memories: [RTLMemory] = []
            var assignments: [RTLAssignment] = []
            var processes: [RTLProcess] = []
            var instances: [RTLInstance] = []
            var generateBlocks: [RTLGenerateBlock] = []

            while !isAtEnd {
                if current.lexeme == "`" {
                    parseCompilerDirective()
                    continue
                }
                if !isPreprocessorActive {
                    _ = advance()
                    continue
                }
                if current.lexeme == "endmodule" {
                    break
                }
                switch current.lexeme {
                case "parameter", "localparam":
                    parameters.append(contentsOf: parseParameterDeclarations(until: ";"))
                    _ = expect(";")
                case "input", "output", "inout":
                    let declarations = parsePortDeclarations()
                    for declaration in declarations {
                        if let position = ports.firstIndex(where: { $0.name == declaration.name }) {
                            ports[position] = declaration
                        } else {
                            ports.append(declaration)
                        }
                    }
                case "wire", "logic", "reg", "integer":
                    let result = parseSignalDeclarations()
                    signals.append(contentsOf: result.signals)
                    memories.append(contentsOf: result.memories)
                case "assign":
                    if let assignment = parseAssignment(nonBlocking: false) {
                        assignments.append(assignment)
                    }
                case "always_comb", "always_ff", "always", "always_latch":
                    if let process = parseProcess() {
                        processes.append(process)
                    }
                case "generate":
                    generateBlocks.append(contentsOf: parseGenerateBlocks())
                case "interface", "program", "package", "class", "primitive", "fork":
                    unsupportedSemantics = true
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "SV_UNSUPPORTED_SEMANTICS",
                        message: "The SystemVerilog construct is outside the supported canonical subset.",
                        entity: current.lexeme,
                        location: current.span,
                        suggestedActions: ["lower_to_supported_rtl_subset", "use_external_frontend"]
                    ))
                    skipUntilSemicolon()
                default:
                    if let instance = parseInstance() {
                        instances.append(contentsOf: instance)
                    } else {
                        diagnostics.append(LogicDiagnostic(
                            severity: .error,
                            code: "SV_PARSE_UNSUPPORTED_ITEM",
                            message: "The module item is not supported by the canonical frontend.",
                            entity: current.lexeme,
                            location: current.span,
                            suggestedActions: ["rewrite_as_supported_rtl", "use_external_frontend"]
                        ))
                        skipUntilSemicolon()
                    }
                }
            }

            let end: LogicSourceLocation
            if match("endmodule") {
                end = previous.span.end
            } else {
                end = current.span.end
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "SV_PARSE_ENDMODULE_MISSING",
                    message: "The module declaration is not terminated by endmodule.",
                    location: current.span,
                    suggestedActions: ["add_endmodule"]
                ))
            }
            let moduleID = StableLogicID.make(kind: "module", path: sourcePath, name: name)
            return RTLModule(
                id: moduleID,
                name: name,
                parameters: uniqueByName(parameters),
                ports: uniqueByName(ports),
                signals: uniqueByName(signals),
                memories: uniqueByName(memories),
                assignments: assignments,
                processes: processes,
                instances: instances,
                generateBlocks: generateBlocks,
                source: LogicSourceSpan(
                    start: start,
                    end: end
                )
            )
        }

        mutating func parsePortHeader() -> [RTLPort] {
            var ports: [RTLPort] = []
            while !isAtEnd && current.lexeme != ")" {
                let direction = parseDirection(default: .input)
                let dataType = parseDataType(default: .logic)
                let signed = match("signed")
                let parsedRange = parseRange()
                guard let name = consumeIdentifier() else {
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "SV_PARSE_PORT_NAME_MISSING",
                        message: "A port declaration requires a name.",
                        location: current.span,
                        suggestedActions: ["add_port_name"]
                    ))
                    skipUntil([",", ")"])
                    _ = match(",")
                    continue
                }
                ports.append(makePort(
                    name: name,
                    direction: direction,
                    dataType: dataType,
                    range: parsedRange.map { $0.range },
                    rangeExpression: parsedRange.map { $0.expression },
                    signed: signed,
                    source: previous.span
                ))
                if !match(",") { break }
            }
            return ports
        }

        mutating func parsePortDeclarations() -> [RTLPort] {
            let direction = parseDirection(default: .input)
            let dataType = parseDataType(default: .logic)
            let signed = match("signed")
            let parsedRange = parseRange()
            var ports: [RTLPort] = []
            while let name = consumeIdentifier() {
                ports.append(makePort(
                    name: name,
                    direction: direction,
                    dataType: dataType,
                    range: parsedRange.map { $0.range },
                    rangeExpression: parsedRange.map { $0.expression },
                    signed: signed,
                    source: previous.span
                ))
                if !match(",") { break }
                if current.lexeme == "input" || current.lexeme == "output" || current.lexeme == "inout" {
                    break
                }
            }
            _ = expect(";")
            return ports
        }

        mutating func parseSignalDeclarations() -> (signals: [RTLSignal], memories: [RTLMemory]) {
            let keyword = advance().lexeme
            let dataType: LogicDataType
            let storage: LogicStorageKind
            switch keyword {
            case "wire": dataType = .wire; storage = .net
            case "reg": dataType = .reg; storage = .register
            case "integer": dataType = .integer; storage = .register
            default: dataType = .logic; storage = .combinational
            }
            let signed = match("signed")
            let parsedRange = parseRange()
            var signals: [RTLSignal] = []
            var memories: [RTLMemory] = []
            while let name = consumeIdentifier() {
                if current.lexeme == "[" {
                    let parsedAddressRange = parseRange()
                    memories.append(RTLMemory(
                        id: StableLogicID.make(kind: "memory", path: sourcePath, name: name),
                        name: name,
                        elementRange: parsedRange.map { $0.range },
                        addressRange: parsedAddressRange.map { $0.range } ?? LogicRange(msb: 0, lsb: 0),
                        elementRangeExpression: parsedRange.map { $0.expression },
                        addressRangeExpression: parsedAddressRange.map { $0.expression },
                        source: previous.span
                    ))
                } else {
                    signals.append(RTLSignal(
                        id: StableLogicID.make(kind: "signal", path: sourcePath, name: name),
                        name: name,
                        dataType: dataType,
                        storage: storage,
                        range: parsedRange.map { $0.range },
                        rangeExpression: parsedRange.map { $0.expression },
                        isSigned: signed,
                        source: previous.span
                    ))
                }
                if !match(",") { break }
            }
            _ = expect(";")
            return (signals, memories)
        }

        mutating func parseParameterDeclarations(until terminator: String) -> [RTLParameter] {
            var parameters: [RTLParameter] = []
            while !isAtEnd && current.lexeme != terminator {
                _ = match("parameter") || match("localparam")
                _ = match("integer")
                guard let name = consumeIdentifier() else {
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "SV_PARSE_PARAMETER_NAME_MISSING",
                        message: "A parameter declaration requires a name.",
                        location: current.span,
                        suggestedActions: ["add_parameter_name"]
                    ))
                    skipUntil([",", terminator])
                    _ = match(",")
                    continue
                }
                _ = expect("=")
                let expression = parseExpression()
                let value = evaluate(expression) ?? 0
                parameters.append(RTLParameter(
                    id: StableLogicID.make(kind: "parameter", path: sourcePath, name: name),
                    name: name,
                    value: value,
                    defaultExpression: expression,
                    source: previous.span
                ))
                parameterValues[name] = value
                if !match(",") { break }
            }
            return parameters
        }

        mutating func parseAssignment(nonBlocking: Bool) -> RTLAssignment? {
            let start = advance().span.start
            let target = parsePrimaryExpression()
            guard match(nonBlocking ? "<=" : "=") else {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "SV_PARSE_ASSIGNMENT_OPERATOR_MISSING",
                    message: "An assignment requires the expected assignment operator.",
                    location: current.span,
                    suggestedActions: ["add_assignment_operator"]
                ))
                skipUntilSemicolon()
                return nil
            }
            let value = parseExpression()
            _ = expect(";")
            let end = previous.span.end
            return RTLAssignment(
                id: StableLogicID.make(kind: "assignment", path: sourcePath, name: "\(start.offset)"),
                target: target,
                value: value,
                nonBlocking: nonBlocking,
                source: LogicSourceSpan(start: start, end: end)
            )
        }

        mutating func parseCompilerDirective() {
            let directiveStart = current.span.start
            guard match("`") else { return }
            guard current.kind == .identifier || current.kind == .keyword else {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "SV_DIRECTIVE_NAME_MISSING",
                    message: "A compiler directive requires a name.",
                    location: current.span,
                    suggestedActions: ["provide_directive_name"]
                ))
                skipCurrentLine(startingAt: directiveStart.line)
                return
            }
            let directive = advance().lexeme

            switch directive {
            case "ifdef", "ifndef":
                parseConditionalStart(
                    directive,
                    location: directiveStart
                )
            case "elsif":
                parseConditionalElseIf(location: directiveStart)
            case "else":
                parseConditionalElse(location: directiveStart)
            case "endif":
                parseConditionalEnd(location: directiveStart)
            case "timescale", "default_nettype", "celldefine", "endcelldefine":
                guard isPreprocessorActive else {
                    skipCurrentLine(startingAt: directiveStart.line)
                    return
                }
                skipCurrentLine(startingAt: directiveStart.line)
            case "include" where allowResolvedIncludes:
                guard isPreprocessorActive else {
                    skipCurrentLine(startingAt: directiveStart.line)
                    return
                }
                skipCurrentLine(startingAt: directiveStart.line)
            case "define":
                guard isPreprocessorActive else {
                    skipCurrentLine(startingAt: directiveStart.line)
                    return
                }
                guard let name = consumeIdentifier() else {
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "SV_DEFINE_NAME_MISSING",
                        message: "A define directive requires a macro name.",
                        location: current.span,
                        suggestedActions: ["provide_macro_name"]
                    ))
                    skipCurrentLine(startingAt: directiveStart.line)
                    return
                }
                let functionLike = current.lexeme == "(" &&
                    current.span.start.line == directiveStart.line &&
                    current.span.start.column == previous.span.end.column
                var parameters: [String] = []
                if functionLike {
                    _ = advance()
                    while !isAtEnd && current.lexeme != ")" && current.span.start.line == directiveStart.line {
                        guard let parameter = consumeIdentifier() else {
                            diagnostics.append(LogicDiagnostic(
                                severity: .error,
                                code: "SV_DEFINE_PARAMETER_MISSING",
                                message: "A function-like macro parameter must be an identifier.",
                                entity: name,
                                location: current.span,
                                suggestedActions: ["use_identifier_macro_parameters"]
                            ))
                            skipUntil([")"])
                            break
                        }
                        parameters.append(parameter)
                        if !match(",") { break }
                    }
                    _ = expect(")", code: "SV_DEFINE_PARAMETER_LIST_UNTERMINATED")
                }
                var replacement: [SystemVerilogToken] = []
                while !isAtEnd && current.span.start.line == directiveStart.line {
                    replacement.append(advance())
                }
                macroDefinitions[name] = MacroDefinition(
                    isFunctionLike: functionLike,
                    parameters: parameters,
                    replacement: replacement
                )
                if !functionLike {
                    var expressionTokens = replacement
                    expressionTokens.append(SystemVerilogToken(
                        kind: .endOfFile,
                        lexeme: "",
                        span: current.span
                    ))
                    var macroState = ParserState(
                        tokens: expressionTokens,
                        sourcePath: sourcePath,
                        macroValues: macroValues,
                        macroDefinitions: macroDefinitions,
                        allowResolvedIncludes: allowResolvedIncludes
                    )
                    let expression = macroState.parseExpression()
                    if macroState.diagnostics.isEmpty, let value = macroState.evaluate(expression) {
                        macroValues[name] = value
                    } else {
                        macroValues.removeValue(forKey: name)
                    }
                } else {
                    macroValues.removeValue(forKey: name)
                }
            default:
                guard isPreprocessorActive else {
                    skipCurrentLine(startingAt: directiveStart.line)
                    return
                }
                unsupportedSemantics = true
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "SV_UNSUPPORTED_DIRECTIVE",
                    message: "The compiler directive is outside the native preprocessing subset.",
                    entity: directive,
                    location: LogicSourceSpan(start: directiveStart, end: current.span.end),
                    suggestedActions: ["preprocess_before_logic_design", "use_supported_compiler_directive"]
                ))
                skipCurrentLine(startingAt: directiveStart.line)
            }
        }

        mutating func parseConditionalStart(
            _ directive: String,
            location: LogicSourceLocation
        ) {
            let parentActive = isPreprocessorActive
            guard let name = consumeIdentifier() else {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "SV_CONDITIONAL_MACRO_MISSING",
                    message: "A conditional compilation directive requires a macro name.",
                    location: current.span,
                    suggestedActions: ["provide_macro_name"]
                ))
                unsupportedSemantics = true
                skipCurrentLine(startingAt: location.line)
                conditionalFrames.append(ConditionalFrame(
                    parentActive: parentActive,
                    branchTaken: false,
                    branchActive: false,
                    elseSeen: false
                ))
                return
            }
            let defined = macroDefinitions[name] != nil
            let condition = directive == "ifdef" ? defined : !defined
            conditionalFrames.append(ConditionalFrame(
                parentActive: parentActive,
                branchTaken: condition,
                branchActive: parentActive && condition,
                elseSeen: false
            ))
            skipCurrentLine(startingAt: location.line)
        }

        mutating func parseConditionalElseIf(location: LogicSourceLocation) {
            guard !conditionalFrames.isEmpty else {
                recordUnmatchedConditional("elsif", location: location)
                skipCurrentLine(startingAt: location.line)
                return
            }
            guard let name = consumeIdentifier() else {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "SV_CONDITIONAL_MACRO_MISSING",
                    message: "An elsif directive requires a macro name.",
                    location: current.span,
                    suggestedActions: ["provide_macro_name"]
                ))
                unsupportedSemantics = true
                skipCurrentLine(startingAt: location.line)
                return
            }
            var frame = conditionalFrames[conditionalFrames.count - 1]
            guard !frame.elseSeen else {
                recordUnmatchedConditional("elsif", location: location)
                skipCurrentLine(startingAt: location.line)
                return
            }
            let condition = macroDefinitions[name] != nil
            frame.branchActive = frame.parentActive && !frame.branchTaken && condition
            frame.branchTaken = frame.branchTaken || condition
            conditionalFrames[conditionalFrames.count - 1] = frame
            skipCurrentLine(startingAt: location.line)
        }

        mutating func parseConditionalElse(location: LogicSourceLocation) {
            guard !conditionalFrames.isEmpty else {
                recordUnmatchedConditional("else", location: location)
                skipCurrentLine(startingAt: location.line)
                return
            }
            var frame = conditionalFrames[conditionalFrames.count - 1]
            guard !frame.elseSeen else {
                recordUnmatchedConditional("else", location: location)
                skipCurrentLine(startingAt: location.line)
                return
            }
            frame.elseSeen = true
            frame.branchActive = frame.parentActive && !frame.branchTaken
            frame.branchTaken = true
            conditionalFrames[conditionalFrames.count - 1] = frame
            skipCurrentLine(startingAt: location.line)
        }

        mutating func parseConditionalEnd(location: LogicSourceLocation) {
            guard !conditionalFrames.isEmpty else {
                recordUnmatchedConditional("endif", location: location)
                skipCurrentLine(startingAt: location.line)
                return
            }
            _ = conditionalFrames.removeLast()
            skipCurrentLine(startingAt: location.line)
        }

        mutating func recordUnmatchedConditional(
            _ directive: String,
            location: LogicSourceLocation
        ) {
            unsupportedSemantics = true
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "SV_CONDITIONAL_UNMATCHED",
                message: "The conditional compilation directive has no matching active block.",
                entity: directive,
                location: LogicSourceSpan(start: location, end: location),
                suggestedActions: ["balance_conditional_directives", "use_external_preprocessor"]
            ))
        }

        mutating func finalizePreprocessor() {
            guard !conditionalFrames.isEmpty else { return }
            unsupportedSemantics = true
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "SV_CONDITIONAL_UNTERMINATED",
                message: "A conditional compilation block is not terminated by endif.",
                location: current.span,
                suggestedActions: ["add_endif", "use_external_preprocessor"]
            ))
            conditionalFrames.removeAll()
        }

        mutating func parseProcess() -> RTLProcess? {
            let keyword = advance().lexeme
            let kind: RTLProcessKind
            switch keyword {
            case "always_ff": kind = .sequential
            case "always_comb": kind = .combinational
            case "always_latch": kind = .latch
            default: kind = .generic
            }
            var sensitivity: [String] = []
            var clockEdge: RTLClockEdge?
            var events: [RTLProcessEvent] = []
            if keyword == "always" || keyword == "always_ff" {
                _ = expect("@")
                if match("*") {
                    sensitivity = ["*"]
                } else if match("(") {
                    if match("*") {
                        sensitivity = ["*"]
                    } else {
                        while !isAtEnd && current.lexeme != ")" {
                            if match("or") || match(",") {
                                continue
                            }
                            let edge: RTLClockEdge?
                            if match("posedge") {
                                edge = .positive
                            } else if match("negedge") {
                                edge = .negative
                            } else {
                                edge = nil
                            }
                            if let name = consumeIdentifier() {
                                sensitivity.append(name)
                                events.append(RTLProcessEvent(signal: name, edge: edge))
                                if clockEdge == nil, let edge {
                                    clockEdge = edge
                                }
                            } else {
                                _ = advance()
                            }
                        }
                    }
                    _ = expect(")")
                }
            }
            guard let statement = parseStatement() else { return nil }
            if keyword == "always_comb" || keyword == "always_latch" {
                sensitivity = inferredSensitivity(from: statement)
                events = sensitivity.map { RTLProcessEvent(signal: $0, edge: nil) }
            }
            return RTLProcess(
                id: StableLogicID.make(kind: "process", path: sourcePath, name: "\(previous.span.start.offset)"),
                kind: kind,
                sensitivity: sensitivity,
                clockEdge: clockEdge,
                events: events,
                statements: [statement],
                source: statementSpan(statement)
            )
        }

        func inferredSensitivity(from statement: RTLStatement) -> [String] {
            var result: [String] = []
            collectReadIdentifiers(from: statement, into: &result)
            return result
        }

        func collectReadIdentifiers(from statement: RTLStatement, into result: inout [String]) {
            switch statement {
            case .assignment(let assignment):
                collectReadIdentifiers(from: assignment.value, into: &result)
                collectReadIdentifiers(from: assignment.target, includeBase: false, into: &result)
            case .block(let statements):
                for child in statements {
                    collectReadIdentifiers(from: child, into: &result)
                }
            case .conditional(let condition, let ifTrue, let ifFalse):
                collectReadIdentifiers(from: condition, into: &result)
                for child in ifTrue + ifFalse {
                    collectReadIdentifiers(from: child, into: &result)
                }
            case .caseStatement(let expression, let items, let defaults),
                 .typedCaseStatement(_, let expression, let items, let defaults):
                collectReadIdentifiers(from: expression, into: &result)
                for item in items {
                    for match in item.matches {
                        collectReadIdentifiers(from: match, into: &result)
                    }
                    for child in item.statements {
                        collectReadIdentifiers(from: child, into: &result)
                    }
                }
                for child in defaults {
                    collectReadIdentifiers(from: child, into: &result)
                }
            case .null:
                break
            }
        }

        func collectReadIdentifiers(
            from expression: RTLExpression,
            includeBase: Bool = true,
            into result: inout [String]
        ) {
            switch expression {
            case .identifier(let name):
                if includeBase, !result.contains(name) {
                    result.append(name)
                }
            case .integer, .string:
                break
            case .unary(_, let operand):
                collectReadIdentifiers(from: operand, into: &result)
            case .binary(_, let left, let right):
                collectReadIdentifiers(from: left, into: &result)
                collectReadIdentifiers(from: right, into: &result)
            case .ternary(let condition, let ifTrue, let ifFalse):
                collectReadIdentifiers(from: condition, into: &result)
                collectReadIdentifiers(from: ifTrue, into: &result)
                collectReadIdentifiers(from: ifFalse, into: &result)
            case .concatenate(let values):
                for value in values {
                    collectReadIdentifiers(from: value, into: &result)
                }
            case .index(let value, let index):
                collectReadIdentifiers(from: value, includeBase: includeBase, into: &result)
                collectReadIdentifiers(from: index, into: &result)
            case .partSelect(let value, let msb, let lsb):
                collectReadIdentifiers(from: value, includeBase: includeBase, into: &result)
                collectReadIdentifiers(from: msb, into: &result)
                collectReadIdentifiers(from: lsb, into: &result)
            }
        }

        mutating func parseStatement() -> RTLStatement? {
            if match(";") { return .null }
            if match("begin") {
                var statements: [RTLStatement] = []
                while !isAtEnd && current.lexeme != "end" {
                    if let statement = parseStatement() { statements.append(statement) } else { break }
                }
                _ = expect("end")
                return .block(statements)
            }
            if match("if") {
                _ = expect("(")
                let condition = parseExpression()
                _ = expect(")")
                guard let trueStatement = parseStatement() else { return nil }
                let falseStatement = match("else") ? parseStatement() : nil
                return .conditional(
                    condition: condition,
                    ifTrue: flatten(trueStatement),
                    ifFalse: falseStatement.map(flatten) ?? []
                )
            }
            if current.lexeme == "case" || current.lexeme == "casex" || current.lexeme == "casez" {
                return parseCaseStatement()
            }
            let start = current.span.start
            let target = parsePrimaryExpression()
            let nonBlocking = match("<=")
            let blocking = nonBlocking || match("=")
            guard blocking else {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "SV_PARSE_STATEMENT_UNSUPPORTED",
                    message: "The procedural statement is not a supported assignment or control statement.",
                    location: current.span,
                    suggestedActions: ["rewrite_as_assignment", "use_supported_if_statement"]
                ))
                skipUntilSemicolon()
                return nil
            }
            let value = parseExpression()
            _ = expect(";")
            return .assignment(RTLAssignment(
                id: StableLogicID.make(kind: "assignment", path: sourcePath, name: "\(start.offset)"),
                target: target,
                value: value,
                nonBlocking: nonBlocking,
                source: LogicSourceSpan(start: start, end: previous.span.end)
            ))
        }

        mutating func parseCaseStatement() -> RTLStatement? {
            let start = current.span.start
            let caseKind: RTLCaseKind
            switch advance().lexeme {
            case "casex": caseKind = .x
            case "casez": caseKind = .z
            default: caseKind = .standard
            }
            _ = expect("(")
            let expression = parseExpression()
            _ = expect(")")
            var items: [RTLCaseItem] = []
            var defaultStatements: [RTLStatement] = []

            while !isAtEnd && current.lexeme != "endcase" {
                if match("default") {
                    _ = expect(":")
                    if let statement = parseStatement() {
                        defaultStatements.append(contentsOf: flatten(statement))
                    }
                    continue
                }

                var matches: [RTLExpression] = [parseExpression()]
                while match(",") {
                    matches.append(parseExpression())
                }
                guard expect(":") else {
                    skipUntil(["endcase"])
                    break
                }
                guard let statement = parseStatement() else {
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "SV_CASE_STATEMENT_MISSING",
                        message: "A case item requires a procedural statement.",
                        location: current.span,
                        suggestedActions: ["add_case_statement"]
                    ))
                    skipUntil(["endcase"])
                    break
                }
                items.append(RTLCaseItem(
                    matches: matches,
                    statements: flatten(statement),
                    source: LogicSourceSpan(start: start, end: previous.span.end)
                ))
            }
            _ = expect("endcase")
            return .typedCaseStatement(
                kind: caseKind,
                expression: expression,
                items: items,
                defaultStatements: defaultStatements
            )
        }

        mutating func parseInstance() -> [RTLInstance]? {
            guard current.kind == .identifier || current.kind == .keyword else { return nil }
            let moduleName = advance().lexeme
            guard current.lexeme == "#" || current.kind == .identifier else {
                index -= 1
                return nil
            }
            var overrides: [String: Int64] = [:]
            if match("#") {
                _ = expect("(")
                while !isAtEnd && current.lexeme != ")" {
                    if match(".") {
                        guard let name = consumeIdentifier() else { break }
                        _ = expect("(")
                        overrides[name] = evaluate(parseExpression()) ?? 0
                        _ = expect(")")
                    } else {
                        _ = advance()
                    }
                    if !match(",") { break }
                }
                _ = expect(")")
            }
            var instances: [RTLInstance] = []
            while let instanceName = consumeIdentifier() {
                guard match("(") else {
                    index -= 1
                    break
                }
                var connections: [RTLPortConnection] = []
                while !isAtEnd && current.lexeme != ")" {
                    var portName = "\(connections.count)"
                    if match(".") {
                        portName = consumeIdentifier() ?? portName
                        _ = expect("(")
                        let expression = parseExpression()
                        _ = expect(")")
                        connections.append(RTLPortConnection(portName: portName, expression: expression, source: previous.span))
                    } else {
                        let expression = parseExpression()
                        connections.append(RTLPortConnection(portName: portName, expression: expression, source: previous.span))
                    }
                    if !match(",") { break }
                }
                _ = expect(")")
                instances.append(RTLInstance(
                    id: StableLogicID.make(kind: "instance", path: sourcePath, name: instanceName),
                    moduleName: moduleName,
                    instanceName: instanceName,
                    parameterOverrides: overrides,
                    connections: connections,
                    source: previous.span
                ))
                if !match(",") { break }
            }
            guard !instances.isEmpty else { return nil }
            _ = expect(";")
            return instances
        }

        mutating func parseGenerateBlocks() -> [RTLGenerateBlock] {
            _ = advance()
            var blocks: [RTLGenerateBlock] = []
            while !isAtEnd && current.lexeme != "endgenerate" {
                if match("for") {
                    if let block = parseGenerateFor() {
                        blocks.append(block)
                    }
                    continue
                }
                if match("if") {
                    blocks.append(contentsOf: parseGenerateIf())
                    continue
                }
                do {
                    unsupportedSemantics = true
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "SV_UNSUPPORTED_GENERATE",
                        message: "Only constant generate-for and generate-if blocks are supported.",
                        entity: current.lexeme,
                        location: current.span,
                        suggestedActions: ["use_constant_generate_construct", "use_explicit_instances"]
                    ))
                    skipUntil(["endgenerate"])
                    break
                }
            }
            _ = expect("endgenerate")
            return blocks
        }

        mutating func parseGenerateIf() -> [RTLGenerateBlock] {
            let start = previous.span.start
            var branches: [(condition: RTLExpression, body: GenerateBody)] = []
            var previousConditions: [RTLExpression] = []

            while true {
                _ = expect("(")
                let condition = parseExpression()
                _ = expect(")")
                guard let body = parseGenerateBody() else { return [] }
                let branchCondition = previousConditions.isEmpty
                    ? condition
                    : .binary(
                        operator: "&&",
                        left: conjunction(previousConditions.map { .unary(operator: "!", operand: $0) }),
                        right: condition
                    )
                branches.append((condition: branchCondition, body: body))
                previousConditions.append(condition)

                guard match("else") else { break }
                guard match("if") else {
                    guard let body = parseGenerateBody() else { return [] }
                    branches.append((
                        condition: conjunction(previousConditions.map { .unary(operator: "!", operand: $0) }),
                        body: body
                    ))
                    break
                }
            }

            guard branches.allSatisfy({ evaluate($0.condition) != nil }) else {
                unsupportedSemantics = true
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "SV_UNSUPPORTED_GENERATE",
                    message: "Generate-if and generate-else-if conditions must be compile-time constant.",
                    entity: "if",
                    location: LogicSourceSpan(start: start, end: current.span.end),
                    suggestedActions: ["make_generate_conditions_constant", "use_explicit_instances"]
                ))
                return []
            }

            return branches.enumerated().map { index, branch in
                RTLGenerateBlock(
                id: StableLogicID.make(kind: "generate", path: sourcePath, name: "\(moduleNameForIDs).\(start.offset).branch\(index)"),
                label: branch.body.label,
                kind: .conditional,
                condition: branch.condition,
                loopVariable: "",
                start: 0,
                limit: 0,
                step: 0,
                instances: branch.body.instances,
                assignments: branch.body.assignments,
                source: LogicSourceSpan(start: start, end: branch.body.end)
                )
            }
        }

        func conjunction(_ expressions: [RTLExpression]) -> RTLExpression {
            expressions.reduce(.integer(value: 1, width: nil, isSigned: true)) { partial, expression in
                .binary(operator: "&&", left: partial, right: expression)
            }
        }

        private struct GenerateBody {
            let label: String
            let instances: [RTLInstance]
            let assignments: [RTLAssignment]
            let end: LogicSourceLocation
        }

        private mutating func parseGenerateBody() -> GenerateBody? {
            guard match("begin") else {
                unsupportedSemantics = true
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "SV_GENERATE_BLOCK_MISSING",
                    message: "A generate construct requires a begin/end body.",
                    location: current.span,
                    suggestedActions: ["add_generate_begin_end"]
                ))
                skipUntil(["endgenerate", "end"])
                return nil
            }
            var label = "gen"
            if match(":") { label = consumeIdentifier() ?? label }
            var instances: [RTLInstance] = []
            var assignments: [RTLAssignment] = []
            while !isAtEnd && current.lexeme != "end" {
                if current.lexeme == "`" {
                    parseCompilerDirective()
                } else if !isPreprocessorActive {
                    _ = advance()
                } else if current.lexeme == "assign" {
                    if let assignment = parseAssignment(nonBlocking: false) { assignments.append(assignment) }
                } else if let parsed = parseInstance() {
                    instances.append(contentsOf: parsed)
                } else {
                    unsupportedSemantics = true
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "SV_GENERATE_ITEM_UNSUPPORTED",
                        message: "The generate body contains an unsupported item.",
                        entity: current.lexeme,
                        location: current.span,
                        suggestedActions: ["use_module_instance_or_continuous_assignment"]
                    ))
                    skipUntil(["end"])
                }
            }
            let end = current.span.end
            _ = expect("end")
            return GenerateBody(label: label, instances: instances, assignments: assignments, end: end)
        }

        mutating func parseGenerateFor() -> RTLGenerateBlock? {
            let start = previous.span.start
            _ = expect("(")
            _ = match("genvar")
            guard let variable = consumeIdentifier() else {
                unsupportedSemantics = true
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "SV_GENERATE_VARIABLE_MISSING",
                    message: "A generate-for block requires a loop variable.",
                    location: current.span,
                    suggestedActions: ["declare_generate_variable"]
                ))
                skipUntil([")"])
                _ = match(")")
                return nil
            }
            _ = expect("=")
            let initialExpression = parseExpression()
            let initial = evaluate(initialExpression)
            _ = expect(";")
            _ = consumeIdentifier()
            let comparison = advance().lexeme
            let limitExpression = parseExpression()
            let limit = evaluate(limitExpression)
            _ = expect(";")
            _ = consumeIdentifier()
            let stepExpression: RTLExpression
            if match("=") {
                _ = consumeIdentifier()
                let stepOperator = current.lexeme
                _ = advance()
                let stepMagnitudeExpression = parseExpression()
                stepExpression = stepOperator == "-"
                    ? .unary(operator: "-", operand: stepMagnitudeExpression)
                    : stepMagnitudeExpression
            } else if match("++") || match("+=") {
                if previous.lexeme == "++" {
                    stepExpression = .integer(value: 1, width: nil, isSigned: true)
                } else {
                    stepExpression = parseExpression()
                }
            } else if match("--") || match("-=") {
                if previous.lexeme == "--" {
                    stepExpression = .integer(value: -1, width: nil, isSigned: true)
                } else {
                    stepExpression = .unary(operator: "-", operand: parseExpression())
                }
            } else {
                stepExpression = .integer(value: 0, width: nil, isSigned: true)
            }
            let stepValue = evaluate(stepExpression)
            _ = expect(")")
            guard let initial, let limit, let stepValue,
                  stepValue != 0,
                  ["<", "<=", ">", ">="].contains(comparison),
                  (comparison == "<" || comparison == "<=") == (stepValue > 0) else {
                unsupportedSemantics = true
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "SV_GENERATE_NON_CONSTANT",
                    message: "Generate-for bounds, comparison, and step must be compile-time constant and directionally consistent.",
                    location: current.span,
                    suggestedActions: ["make_generate_bounds_constant", "use_supported_generate_comparison", "use_explicit_instances"]
                ))
                skipUntil(["end"])
                _ = match("end")
                return nil
            }
            let normalizedLimitExpression: RTLExpression
            let normalizedLimit: Int64?
            switch comparison {
            case "<=":
                normalizedLimitExpression = .binary(
                    operator: "+",
                    left: limitExpression,
                    right: .integer(value: 1, width: nil, isSigned: true)
                )
                let adjustedLimit = limit.addingReportingOverflow(1)
                normalizedLimit = adjustedLimit.overflow ? nil : adjustedLimit.partialValue
            case ">=":
                normalizedLimitExpression = .binary(
                    operator: "-",
                    left: limitExpression,
                    right: .integer(value: 1, width: nil, isSigned: true)
                )
                let adjustedLimit = limit.subtractingReportingOverflow(1)
                normalizedLimit = adjustedLimit.overflow ? nil : adjustedLimit.partialValue
            default:
                normalizedLimitExpression = limitExpression
                normalizedLimit = limit
            }
            guard let normalizedLimit else {
                unsupportedSemantics = true
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "SV_GENERATE_NON_CONSTANT",
                    message: "Generate-for bounds overflow during inclusive-bound normalization.",
                    location: current.span,
                    suggestedActions: ["use_safe_generate_bounds", "use_explicit_instances"]
                ))
                skipUntil(["end"])
                _ = match("end")
                return nil
            }
            guard let body = parseGenerateBody() else { return nil }
            return RTLGenerateBlock(
                id: StableLogicID.make(kind: "generate", path: sourcePath, name: "\(moduleNameForIDs).\(start.offset)"),
                label: body.label,
                loopVariable: variable,
                start: initial,
                limit: normalizedLimit,
                step: stepValue,
                startExpression: initialExpression,
                limitExpression: normalizedLimitExpression,
                stepExpression: stepExpression,
                instances: body.instances,
                assignments: body.assignments,
                source: LogicSourceSpan(start: start, end: body.end)
            )
        }

        mutating func parseExpression(minPrecedence: Int = 0) -> RTLExpression {
            var left = parsePrimaryExpression()
            let precedences: [String: Int] = [
                "||": 1, "&&": 2, "|": 3, "^": 4, "&": 5, "==": 6, "!=": 6, "===": 6, "!==": 6,
                "<": 7, ">": 7, "<=": 7, ">=": 7, "<<": 8, ">>": 8, "+": 9, "-": 9, "*": 10,
                "/": 10, "%": 10
            ]
            while let precedence = precedences[current.lexeme], precedence >= minPrecedence {
                let operation = advance().lexeme
                let right = parseExpression(minPrecedence: precedence + 1)
                left = .binary(operator: operation, left: left, right: right)
            }
            if minPrecedence == 0, match("?") {
                let ifTrue = parseExpression()
                _ = expect(":")
                let ifFalse = parseExpression()
                left = .ternary(condition: left, ifTrue: ifTrue, ifFalse: ifFalse)
            }
            return left
        }

        mutating func parsePrimaryExpression() -> RTLExpression {
            if match("`") {
                guard let name = consumeIdentifier() else {
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "SV_MACRO_NAME_MISSING",
                        message: "A macro reference requires a name.",
                        location: current.span,
                        suggestedActions: ["provide_macro_name"]
                    ))
                    return .integer(value: 0, width: nil, isSigned: false)
                }
                if let value = macroValues[name] {
                    return .integer(value: value, width: nil, isSigned: true)
                }
                guard let definition = macroDefinitions[name] else {
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "SV_MACRO_UNRESOLVED",
                        message: "The macro reference is not defined in the source set.",
                        entity: name,
                        location: previous.span,
                        suggestedActions: ["define_macro", "preprocess_before_logic_design"]
                    ))
                    return .identifier(name)
                }
                guard !expandingMacros.contains(name) else {
                    unsupportedSemantics = true
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "SV_MACRO_RECURSIVE",
                        message: "Macro expansion is recursive and cannot be evaluated deterministically.",
                        entity: name,
                        location: previous.span,
                        suggestedActions: ["remove_macro_recursion", "preprocess_before_logic_design"]
                    ))
                    return .identifier(name)
                }
                expandingMacros.insert(name)
                defer { expandingMacros.remove(name) }

                let expandedTokens: [SystemVerilogToken]
                if !definition.isFunctionLike {
                    expandedTokens = definition.replacement
                } else {
                    guard current.lexeme == "(" else {
                        diagnostics.append(LogicDiagnostic(
                            severity: .error,
                            code: "SV_MACRO_ARGUMENTS_MISSING",
                            message: "A function-like macro reference requires an argument list.",
                            entity: name,
                            location: current.span,
                            suggestedActions: ["provide_macro_arguments"]
                        ))
                        return .identifier(name)
                    }
                    let arguments = consumeMacroArguments()
                    guard arguments.count == definition.parameters.count else {
                        diagnostics.append(LogicDiagnostic(
                            severity: .error,
                            code: "SV_MACRO_ARGUMENT_COUNT",
                            message: "The macro invocation does not provide the declared number of arguments.",
                            entity: name,
                            location: previous.span,
                            suggestedActions: ["correct_macro_argument_count"]
                        ))
                        return .identifier(name)
                    }
                    let substitutions = Dictionary(uniqueKeysWithValues: zip(definition.parameters, arguments))
                    expandedTokens = definition.replacement.flatMap { token in
                        guard token.kind == .identifier, let replacement = substitutions[token.lexeme] else {
                            return [token]
                        }
                        return replacement
                    }
                }
                guard !expandedTokens.isEmpty else {
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "SV_MACRO_EMPTY_EXPRESSION",
                        message: "An empty macro cannot be used as an expression.",
                        entity: name,
                        location: previous.span,
                        suggestedActions: ["provide_macro_replacement_tokens"]
                    ))
                    return .integer(value: 0, width: nil, isSigned: false)
                }
                tokens.insert(contentsOf: expandedTokens, at: index)
                return parsePrimaryExpression()
            }
            if match("(") {
                let expression = parseExpression()
                _ = expect(")")
                return parsePostfix(expression)
            }
            if match("{") {
                var values: [RTLExpression] = []
                while !isAtEnd && current.lexeme != "}" {
                    values.append(parseExpression())
                    if !match(",") { break }
                }
                _ = expect("}")
                return .concatenate(values)
            }
            if current.lexeme == "!" || current.lexeme == "~" || current.lexeme == "+" || current.lexeme == "-" {
                let operation = advance().lexeme
                return .unary(operator: operation, operand: parsePrimaryExpression())
            }
            let token = advance()
            if token.kind == .number {
                let parsed = parseNumber(token.lexeme)
                return .integer(value: parsed.value, width: parsed.width, isSigned: parsed.isSigned)
            }
            if token.kind == .string {
                return .string(token.lexeme)
            }
            return parsePostfix(.identifier(token.lexeme))
        }

        mutating func consumeMacroArguments() -> [[SystemVerilogToken]] {
            _ = expect("(")
            var arguments: [[SystemVerilogToken]] = [[]]
            var depth = 0
            while !isAtEnd {
                if current.lexeme == "(" {
                    depth += 1
                    arguments[arguments.count - 1].append(advance())
                    continue
                }
                if current.lexeme == ")" {
                    if depth == 0 {
                        _ = advance()
                        if arguments.count == 1, arguments[0].isEmpty {
                            return []
                        }
                        return arguments
                    }
                    depth -= 1
                    arguments[arguments.count - 1].append(advance())
                    continue
                }
                if current.lexeme == "," && depth == 0 {
                    _ = advance()
                    arguments.append([])
                    continue
                }
                arguments[arguments.count - 1].append(advance())
            }
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "SV_MACRO_ARGUMENT_LIST_UNTERMINATED",
                message: "A function-like macro argument list is not terminated.",
                location: current.span,
                suggestedActions: ["close_macro_argument_list"]
            ))
            return arguments
        }

        mutating func parsePostfix(_ expression: RTLExpression) -> RTLExpression {
            var result = expression
            while match("[") {
                let first = parseExpression()
                if match(":") {
                    let second = parseExpression()
                    result = .partSelect(value: result, msb: first, lsb: second)
                } else {
                    result = .index(value: result, index: first)
                }
                _ = expect("]")
            }
            return result
        }

        mutating func parseRange() -> (range: LogicRange, expression: RTLRangeExpression)? {
            guard match("[") else { return nil }
            let msbExpression = parseExpression()
            let msb = evaluate(msbExpression) ?? 0
            _ = expect(":")
            let lsbExpression = parseExpression()
            let lsb = evaluate(lsbExpression) ?? 0
            _ = expect("]")
            return (
                range: LogicRange(msb: Int(msb), lsb: Int(lsb)),
                expression: RTLRangeExpression(msb: msbExpression, lsb: lsbExpression)
            )
        }

        mutating func parseDirection(default fallback: LogicDirection) -> LogicDirection {
            if match("input") { return .input }
            if match("output") { return .output }
            if match("inout") { return .inOut }
            return fallback
        }

        mutating func parseDataType(default fallback: LogicDataType) -> LogicDataType {
            if match("wire") { return .wire }
            if match("logic") { return .logic }
            if match("reg") { return .reg }
            if match("integer") { return .integer }
            return fallback
        }

        mutating func consumeIdentifier() -> String? {
            guard current.kind == .identifier else { return nil }
            return advance().lexeme
        }

        mutating func skipUntilSemicolon() {
            skipUntil([";"])
            _ = match(";")
        }

        mutating func skipCurrentLine(startingAt line: Int) {
            while !isAtEnd && current.span.start.line == line {
                _ = advance()
            }
        }

        mutating func skipUntil(_ delimiters: Set<String>) {
            while !isAtEnd && !delimiters.contains(current.lexeme) { _ = advance() }
        }

        func makePort(
            name: String,
            direction: LogicDirection,
            dataType: LogicDataType,
            range: LogicRange?,
            rangeExpression: RTLRangeExpression?,
            signed: Bool,
            source: LogicSourceSpan
        ) -> RTLPort {
            RTLPort(
                id: StableLogicID.make(kind: "port", path: sourcePath, name: name),
                name: name,
                direction: direction,
                dataType: dataType,
                range: range,
                rangeExpression: rangeExpression,
                isSigned: signed,
                source: source
            )
        }

        func evaluate(_ expression: RTLExpression) -> Int64? {
            switch expression {
            case .integer(let value, _, _): return value
            case .identifier(let name): return parameterValues[name] ?? macroValues[name]
            case .unary(let operation, let operand):
                guard let value = evaluate(operand) else { return nil }
                switch operation { case "-": return -value; case "+": return value; case "~": return ~value; case "!": return value == 0 ? 1 : 0; default: return nil }
            case .binary(let operation, let left, let right):
                guard let lhs = evaluate(left), let rhs = evaluate(right) else { return nil }
                switch operation {
                case "+": return lhs + rhs; case "-": return lhs - rhs; case "*": return lhs * rhs
                case "/": return rhs == 0 ? nil : lhs / rhs; case "%": return rhs == 0 ? nil : lhs % rhs
                case "&": return lhs & rhs; case "|": return lhs | rhs; case "^": return lhs ^ rhs
                case "<<": return lhs << rhs; case ">>": return lhs >> rhs
                case "==", "===": return lhs == rhs ? 1 : 0; case "!=", "!==": return lhs != rhs ? 1 : 0
                case "<": return lhs < rhs ? 1 : 0; case ">": return lhs > rhs ? 1 : 0; case "<=": return lhs <= rhs ? 1 : 0; case ">=": return lhs >= rhs ? 1 : 0
                case "&&": return lhs != 0 && rhs != 0 ? 1 : 0; case "||": return lhs != 0 || rhs != 0 ? 1 : 0
                default: return nil
                }
            case .ternary(let condition, let ifTrue, let ifFalse):
                guard let conditionValue = evaluate(condition) else { return nil }
                return evaluate(conditionValue != 0 ? ifTrue : ifFalse)
            default: return nil
            }
        }

        func parseNumber(_ raw: String) -> (value: Int64, width: Int?, isSigned: Bool) {
            let cleaned = raw.replacingOccurrences(of: "_", with: "")
            guard let quote = cleaned.firstIndex(of: "'") else { return (Int64(cleaned) ?? 0, nil, false) }
            let width = Int(cleaned[..<quote])
            let suffix = cleaned[cleaned.index(after: quote)...]
            guard let base = suffix.first else { return (0, width, false) }
            let digits = suffix.dropFirst().replacingOccurrences(of: "?", with: "0")
            let radix: Int
            switch base.lowercased() { case "b": radix = 2; case "o": radix = 8; case "d": radix = 10; case "h": radix = 16; default: radix = 10 }
            return (Int64(digits, radix: radix) ?? 0, width, suffix.first?.isUppercase == true)
        }

        func flatten(_ statement: RTLStatement) -> [RTLStatement] {
            if case .block(let statements) = statement { return statements }
            return [statement]
        }

        func statementSpan(_ statement: RTLStatement) -> LogicSourceSpan? {
            switch statement {
            case .assignment(let assignment): return assignment.source
            case .block(let statements): return statements.compactMap(statementSpan).first
            case .conditional: return nil
            case .caseStatement, .typedCaseStatement: return nil
            case .null: return nil
            }
        }

        func expressionSpan(_ expression: RTLExpression) -> LogicSourceSpan? {
            switch expression {
            case .identifier, .integer, .string:
                return previous.span
            case .unary(_, let operand):
                return expressionSpan(operand)
            case .binary(_, let left, let right):
                return expressionSpan(left) ?? expressionSpan(right)
            case .ternary(let condition, let ifTrue, let ifFalse):
                return expressionSpan(condition) ?? expressionSpan(ifTrue) ?? expressionSpan(ifFalse)
            case .concatenate(let values):
                return values.compactMap(expressionSpan).first
            case .index(let value, let index):
                return expressionSpan(value) ?? expressionSpan(index)
            case .partSelect(let value, let msb, let lsb):
                return expressionSpan(value) ?? expressionSpan(msb) ?? expressionSpan(lsb)
            }
        }

        func uniqueByName<T>(_ values: [T]) -> [T] where T: Sendable & Hashable {
            var result: [T] = []
            var seen = Set<String>()
            for value in values {
                let name: String
                switch value {
                case let value as RTLParameter: name = value.name
                case let value as RTLPort: name = value.name
                case let value as RTLSignal: name = value.name
                case let value as RTLMemory: name = value.name
                default: name = String(describing: value)
                }
                if seen.insert(name).inserted { result.append(value) }
            }
            return result
        }
    }
}
