import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogSourcePreprocessor {
    mutating func expand(_ selected: Int, source: borrowing SystemVerilogSourceText, start: Int,
                         afterName: Int, end: Int, output: inout SystemVerilogTextBuffer,
                         context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        for offset in expansions.indices {
            try context.charge(.workUnits)
            guard expansions[offset] != selected else {
                throw try failure(source, start..<afterName, "SV_PP_MACRO_CYCLE", "Recursive macro expansion is outside the profile")
            }
        }
        try expansions.append(selected, receipt: &receipt, bytes: &storageBytes, context: &context)
        defer { _ = expansions.popLast() }
        let definition = macros[selected]
        let first = arguments.count
        defer { arguments.truncate(first) }
        let after: Int
        if let parameters = definition.parameters {
            after = try actuals(source, afterName: afterName, end: end, expected: parameters.count, context: &context)
        } else { after = afterName }
        let origin = try source.origin(for: start..<after)
        let anchor = (source.root, origin)
        let normalized = try normalizedBody(definition.body, anchor: anchor, context: &context)
        let instantiated = try substitute(normalized, parameters: definition.parameters,
            actuals: first..<arguments.count, anchor: anchor, context: &context)
        arguments.truncate(first)

        // Rescanning must see caller tokens after the replacement: an object macro
        // can name a function macro whose argument list occurs in the caller.
        // SourceText currently owns contiguous bytes, so this admitted suffix copy
        // is required at this boundary; its full overlap and work are charged.
        var joined = try SystemVerilogTextBuffer(context: &context)
        let boundary: Int
        do throws(LogicKernelError) {
            try joined.append(instantiated, range: 0..<instantiated.byteCount, context: &context)
            // Terminate definition-line comments and preserve token separation.
            try joined.appendSeparator(anchor: anchor, context: &context)
            boundary = joined.count
            try joined.append(source, range: after..<end, context: &context)
        } catch { try joined.release(context: &context); throw error }
        let text = try joined.finish(root: source.root, terminalOrigin: source.origin(for: end..<end), context: &context)
        let consumed = try scan(text, range: 0..<text.byteCount, directivesAllowed: false,
            stopBefore: boundary, output: &output, context: &context)
        return after + max(0, consumed - boundary)
    }

    mutating func actuals(_ source: borrowing SystemVerilogSourceText, afterName: Int, end: Int, expected: Int,
                         context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        let delimiterStart = delimiters.count
        defer { delimiters.truncate(delimiterStart) }
        return try source.withBytes { (bytes: borrowing Span<UInt8>) throws(LogicKernelError) in
            var index = try trivia(afterName, end: end, bytes: bytes, source: source, context: &context)
            guard index < end, bytes[index] == 40 else {
                throw try failure(source, afterName..<index, "SV_PP_ARGUMENT_LIST", "Function macro requires an actual argument list")
            }
            index += 1; var begin = index; var count = 0
            while index < end {
                try context.charge(.workUnits)
                let byte = bytes[index]
                if byte == 34 { index = try quoted(index, end: end, bytes: bytes, source: source, strict: true, context: &context); continue }
                if byte == 47, index + 1 < end, bytes[index + 1] == 47 || bytes[index + 1] == 42 {
                    index = try comment(index, end: end, bytes: bytes, source: source, context: &context); continue
                }
                if byte == 92 {
                    index += 1
                    while index < end && !Self.isSpace(bytes[index]) { try context.charge(.workUnits); index += 1 }
                    continue
                }
                if delimiters.count == delimiterStart && (byte == 44 || byte == 41) {
                    let empty = try trivia(begin, end: index, bytes: bytes, source: source, context: &context) == index
                    if byte == 44 || count > 0 || expected != 0 || !empty {
                        try arguments.append(Name(source: copy source, range: begin..<index),
                            receipt: &receipt, bytes: &storageBytes, context: &context)
                        count += 1
                    }
                    if byte == 41 {
                        guard count == expected else {
                            throw try failure(source, afterName..<(index + 1), "SV_PP_ARGUMENT_COUNT", "Macro actual and formal counts differ")
                        }
                        return index + 1
                    }
                    begin = index + 1
                } else if byte == 40 || byte == 91 || byte == 123 {
                    guard delimiters.count - delimiterStart < maximumNesting else {
                        throw try failure(source, index..<(index + 1), "SV_PP_NESTING", "Macro argument nesting exceeds the selected profile")
                    }
                    let close: UInt8 = byte == 40 ? 41 : (byte == 91 ? 93 : 125)
                    try delimiters.append(close, receipt: &receipt, bytes: &storageBytes, context: &context)
                } else if byte == 41 || byte == 93 || byte == 125 {
                    guard delimiters.count > delimiterStart, delimiters[delimiters.count - 1] == byte else {
                        throw try failure(source, index..<(index + 1), "SV_PP_ARGUMENT_DELIMITER", "Macro argument delimiters do not match")
                    }
                    _ = delimiters.popLast()
                }
                index += 1
            }
            throw try failure(source, afterName..<end, "SV_PP_ARGUMENT_LIST", "Macro actual argument list is not closed")
        }
    }

    mutating func normalizedBody(_ body: borrowing Name, anchor: (LogicSourceDocument, LogicKernelSourceRange),
                                 context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogSourceText {
        var output = try SystemVerilogTextBuffer(context: &context)
        do throws(LogicKernelError) {
            try body.source.withBytes { (bytes: borrowing Span<UInt8>) throws(LogicKernelError) in
                var index = body.range.lowerBound; var begin = index
                while index < body.range.upperBound {
                    try context.charge(.workUnits)
                    if let next = continuation(index, end: body.range.upperBound, bytes: bytes) {
                        try output.append(body.source, range: begin..<index, anchor: anchor, context: &context)
                        index = next; begin = index
                    } else { index += 1 }
                }
                try output.append(body.source, range: begin..<index, anchor: anchor, context: &context)
            }
        } catch { try output.release(context: &context); throw error }
        return try output.finish(root: anchor.0, terminalOrigin: LogicKernelSourceRange(artifactID: anchor.1.artifactID,
            byteRange: anchor.1.byteRange.upperBound..<anchor.1.byteRange.upperBound), context: &context)
    }

    mutating func substitute(_ body: borrowing SystemVerilogSourceText, parameters: Range<Int>?, actuals: Range<Int>,
                             anchor: (LogicSourceDocument, LogicKernelSourceRange), context: inout LogicKernelContext)
        throws(LogicKernelError) -> SystemVerilogSourceText {
        guard let parameters else { return copy body }
        let capacity = body.byteCount.addingReportingOverflow(1)
        guard !capacity.overflow else { throw .invalidInput("Macro token count overflow") }
        let tokens = try SystemVerilogByteLexer().tokenize(body, maximumTokens: capacity.partialValue, context: &context)
        var output = try SystemVerilogTextBuffer(context: &context)
        do throws(LogicKernelError) {
            try tokens.withTokens { (tokens: borrowing Span<SystemVerilogLexicalToken>) throws(LogicKernelError) in
                var pending = 0
                for index in 0..<tokens.count where tokens[index].kind == .identifier {
                    let token = tokens[index]
                    let name = Name(source: copy body, range: token.byteRange)
                    for formal in parameters {
                        if try equal(name, formals[formal], context: &context) {
                            try output.append(body, range: pending..<token.byteRange.lowerBound, context: &context)
                            let argument = arguments[actuals.lowerBound + formal - parameters.lowerBound]
                            try output.append(argument.source, range: argument.range, anchor: anchor, context: &context)
                            pending = token.byteRange.upperBound
                            break
                        }
                    }
                }
                try output.append(body, range: pending..<body.byteCount, context: &context)
            }
        } catch { try output.release(context: &context); throw error }
        return try output.finish(root: anchor.0, terminalOrigin: LogicKernelSourceRange(artifactID: anchor.1.artifactID,
            byteRange: anchor.1.byteRange.upperBound..<anchor.1.byteRange.upperBound), context: &context)
    }
}
