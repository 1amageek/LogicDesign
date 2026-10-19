import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogSourcePreprocessor {
    mutating func scan(_ source: borrowing SystemVerilogSourceText, range: Range<Int>, directivesAllowed: Bool, stopBefore: Int? = nil,
                      output: inout SystemVerilogTextBuffer, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        guard depth < maximumNesting else {
            throw try failure(source, range.lowerBound..<range.lowerBound, "SV_PP_NESTING", "Preprocessing nesting exceeds the selected profile")
        }
        depth += 1; defer { depth -= 1 }
        return try source.withBytes { (bytes: borrowing Span<UInt8>) throws(LogicKernelError) in
            var index = range.lowerBound; var pending = index
            while index < (stopBefore ?? range.upperBound) {
                try context.charge(.workUnits)
                let byte = bytes[index]
                if byte == 47, index + 1 < range.upperBound, bytes[index + 1] == 47 || bytes[index + 1] == 42 {
                    index = try comment(index, end: range.upperBound, bytes: bytes, source: source, context: &context); continue
                }
                if byte == 34 {
                    index = try quoted(index, end: range.upperBound, bytes: bytes, source: source, strict: active, context: &context); continue
                }
                if byte == 92 {
                    index += 1
                    while index < range.upperBound && !Self.isSpace(bytes[index]) { try context.charge(.workUnits); index += 1 }
                    continue
                }
                guard byte == 96 else { index += 1; continue }
                if active { try output.append(source, range: pending..<index, context: &context) }
                let start = index; index += 1
                guard index < range.upperBound, Self.isNameStart(bytes[index]) else {
                    if !active { pending = index; continue }
                    throw try failure(source, start..<index, "SV_PP_MACRO_OPERATOR_UNSUPPORTED", "Macro quoting, pasting and non-identifier names are outside the profile")
                }
                let nameStart = index
                while index < range.upperBound && Self.isNameByte(bytes[index]) { try context.charge(.workUnits); index += 1 }
                let name = Name(source: copy source, range: nameStart..<index)
                if let directive = try directive(name, context: &context) {
                    guard directivesAllowed else {
                        throw try failure(source, start..<index, "SV_PP_EXPANDED_DIRECTIVE", "Compiler directives created by macro expansion are outside the profile")
                    }
                    let line = try lineEnd(index, end: range.upperBound, bytes: bytes, context: &context)
                    try handle(directive, source: source, start: start, content: index..<line.contentEnd,
                        output: &output, context: &context)
                    if active { try output.append(source, range: line.contentEnd..<line.after, context: &context) }
                    index = line.after
                } else if active {
                    guard let selected = try macro(name, context: &context) else {
                        throw try failure(source, start..<index, "SV_PP_UNDEFINED_MACRO", "Undefined macro or unsupported compiler directive")
                    }
                    index = try expand(selected, source: source, start: start, afterName: index, end: range.upperBound,
                        output: &output, context: &context)
                }
                pending = index
            }
            if active { try output.append(source, range: pending..<index, context: &context) }
            return index
        }
    }

    func lineEnd(_ start: Int, end: Int, bytes: borrowing Span<UInt8>, context: inout LogicKernelContext)
        throws(LogicKernelError) -> (contentEnd: Int, after: Int) {
        var index = start
        while index < end {
            try context.charge(.workUnits)
            if let next = continuation(index, end: end, bytes: bytes) { index = next; continue }
            if bytes[index] == 10 { return (index, index + 1) }
            if bytes[index] == 13 { return (index, index + (index + 1 < end && bytes[index + 1] == 10 ? 2 : 1)) }
            index += 1
        }
        return (end, end)
    }

    func continuation(_ index: Int, end: Int, bytes: borrowing Span<UInt8>) -> Int? {
        guard bytes[index] == 92, index + 1 < end else { return nil }
        if bytes[index + 1] == 10 { return index + 2 }
        if bytes[index + 1] == 13 { return index + (index + 2 < end && bytes[index + 2] == 10 ? 3 : 2) }
        return nil
    }

    func comment(_ start: Int, end: Int, bytes: borrowing Span<UInt8>, source: borrowing SystemVerilogSourceText,
                 context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        var index = start + 2
        if bytes[start + 1] == 47 {
            while index < end && bytes[index] != 10 && bytes[index] != 13 { try context.charge(.workUnits); index += 1 }
            return index
        }
        while index < end {
            try context.charge(.workUnits)
            if bytes[index] == 42, index + 1 < end, bytes[index + 1] == 47 { return index + 2 }
            index += 1
        }
        throw try failure(source, start..<end, "SV_PP_UNCLOSED_COMMENT", "Preprocessing block comment is not closed")
    }

    func quoted(_ start: Int, end: Int, bytes: borrowing Span<UInt8>, source: borrowing SystemVerilogSourceText,
                strict: Bool, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        var index = start + 1
        while index < end {
            try context.charge(.workUnits)
            if bytes[index] == 34 { return index + 1 }
            if bytes[index] == 10 || bytes[index] == 13 { break }
            if bytes[index] == 92, index + 1 < end { index += 2 } else { index += 1 }
        }
        if !strict { return index }
        throw try failure(source, start..<index, "SV_PP_UNCLOSED_STRING", "Preprocessing string is not closed")
    }

    func trivia(_ start: Int, end: Int, bytes: borrowing Span<UInt8>, source: borrowing SystemVerilogSourceText,
                context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        var index = start
        while index < end {
            try context.charge(.workUnits)
            if Self.isSpace(bytes[index]) { index += 1 }
            else if let next = continuation(index, end: end, bytes: bytes) { index = next }
            else if bytes[index] == 47, index + 1 < end, bytes[index + 1] == 47 || bytes[index + 1] == 42 {
                index = try comment(index, end: end, bytes: bytes, source: source, context: &context)
            } else { break }
        }
        return index
    }

    func readName(_ start: Int, end: Int, bytes: borrowing Span<UInt8>, source: borrowing SystemVerilogSourceText,
                  context: inout LogicKernelContext) throws(LogicKernelError) -> Name {
        let begin = try trivia(start, end: end, bytes: bytes, source: source, context: &context)
        guard begin < end, Self.isNameStart(bytes[begin]) else {
            throw try failure(source, begin..<begin, "SV_PP_EXPECTED_NAME", "Compiler directive requires an ASCII identifier")
        }
        var after = begin + 1
        while after < end && Self.isNameByte(bytes[after]) { try context.charge(.workUnits); after += 1 }
        return Name(source: copy source, range: begin..<after)
    }

    func requireEnd(_ start: Int, end: Int, bytes: borrowing Span<UInt8>, source: borrowing SystemVerilogSourceText,
                    context: inout LogicKernelContext) throws(LogicKernelError) {
        let after = try trivia(start, end: end, bytes: bytes, source: source, context: &context)
        guard after == end else { throw try failure(source, after..<end, "SV_PP_DIRECTIVE_TRAILING_TEXT", "Unexpected compiler directive arguments") }
    }
}
