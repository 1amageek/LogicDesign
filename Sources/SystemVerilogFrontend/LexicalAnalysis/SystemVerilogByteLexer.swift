import CircuiteFoundation
import LogicIR
import LogicKernelCore

public struct SystemVerilogByteLexer: SystemVerilogTokenizing {
    private static let operators = ["<<<=", ">>>=", "===", "!==", "<<<", ">>>", "&&&", "<<=", ">>=", "**", "<=", ">=",
                                    "==", "!=", "&&", "||", "<<", ">>", "++", "--", "+=", "-=", "*=", "/=",
                                    "%=", "&=", "|=", "^=", "~&", "~|", "~^", "^~", "+:", "-:", "::", "->", "=>"]
    public init() {}

    @available(macOS 26.0, *)
    public func tokenize(_ source: borrowing LogicSourceDocument, maximumTokens: Int,
                         context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogTokenStream {
        try tokenize(SystemVerilogSourceText(source), maximumTokens: maximumTokens, context: &context)
    }

    @available(macOS 26.0, *)
    package func tokenize(_ source: borrowing SystemVerilogSourceText, maximumTokens: Int,
                          context: inout LogicKernelContext) throws(LogicKernelError) -> SystemVerilogTokenStream {
        guard maximumTokens > 0 else { throw .invalidInput("Token capacity must include EOF") }
        try context.require(.expansion, amount: UInt64(maximumTokens))
        let bytes = UInt64(maximumTokens).multipliedReportingOverflow(by: UInt64(MemoryLayout<SystemVerilogLexicalToken>.stride))
        guard !bytes.overflow else { throw .invalidInput("Token storage overflow") }
        _ = try context.reserveStorage(byteCount: bytes.partialValue)
        let tokens = try source.withBytes { (bytes: borrowing Span<UInt8>) throws(LogicKernelError) in
            try scan(bytes, source: source, maximumTokens: maximumTokens, context: &context)
        }
        // Retain the immutable source owner so token ranges remain usable after this borrow.
        return SystemVerilogTokenStream(source: copy source, tokens: tokens)
    }

    @available(macOS 26.0, *)
    private func scan(_ bytes: borrowing Span<UInt8>, source: borrowing SystemVerilogSourceText,
                      maximumTokens: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) -> [SystemVerilogLexicalToken] {
        var tokens: [SystemVerilogLexicalToken] = []; tokens.reserveCapacity(maximumTokens)
        var index = 0
        while index < bytes.count {
            try context.checkpoint()
            let start = index; let byte = bytes[index]
            if Self.isSpace(byte) {
                try context.charge(.workUnits); index += 1; continue
            }
            if byte == 47, index + 1 < bytes.count, bytes[index + 1] == 47 {
                repeat { try context.charge(.workUnits); index += 1 } while index < bytes.count && bytes[index] != 10
                continue
            }
            if byte == 47, index + 1 < bytes.count, bytes[index + 1] == 42 {
                try context.charge(.workUnits, amount: 2); index += 2
                var closed = false
                while index < bytes.count {
                    if bytes[index] == 42, index + 1 < bytes.count, bytes[index + 1] == 47 {
                        try context.charge(.workUnits, amount: 2); index += 2; closed = true; break
                    }
                    try context.charge(.workUnits); index += 1
                }
                guard closed else { throw try failure("SV_LEX_UNTERMINATED_COMMENT", start..<index, source: source) }
                continue
            }
            let kind: SystemVerilogLexicalToken.Kind
            if byte == 34 {
                kind = .string
                try context.charge(.workUnits); index += 1
                var closed = false
                while index < bytes.count {
                    let next = bytes[index]
                    guard next != 10, next != 13 else { throw try failure("SV_LEX_UNTERMINATED_STRING", start..<index, source: source) }
                    try context.charge(.workUnits); index += 1
                    if next == 34 { closed = true; break }
                    if next == 92, index < bytes.count {
                        try context.charge(.workUnits); index += 1
                        if bytes[index - 1] == 13, index < bytes.count, bytes[index] == 10 {
                            try context.charge(.workUnits); index += 1
                        }
                    }
                }
                guard closed else { throw try failure("SV_LEX_UNTERMINATED_STRING", start..<index, source: source) }
            } else if byte == 92 {
                kind = .escapedIdentifier
                repeat { try context.charge(.workUnits); index += 1 } while index < bytes.count && !Self.isSpace(bytes[index])
                guard index > start + 1 else { throw try failure("SV_LEX_EMPTY_IDENTIFIER", start..<index, source: source) }
            } else if Self.isLetter(byte) || byte == 95 || byte == 36 {
                kind = .identifier
                repeat { try context.charge(.workUnits); index += 1 } while index < bytes.count && Self.isIdentifierByte(bytes[index])
            } else if Self.isDigit(byte) || byte == 39 {
                kind = .number
                try scanNumber(bytes, index: &index, context: &context)
            } else {
                var matched = 0
                for candidate in Self.operators where candidate.utf8.count <= bytes.count - index {
                    var offset = 0; var equal = true
                    for value in candidate.utf8 {
                        try context.charge(.workUnits)
                        if bytes[index + offset] != value { equal = false; break }
                        offset += 1
                    }
                    if equal { matched = candidate.utf8.count; break }
                }
                if matched > 0 { kind = .operator; index += matched }
                else if "()[]{};,:.@#?`".utf8.contains(byte) { kind = .punctuation; try context.charge(.workUnits); index += 1 }
                else if "+-*/%<>=!~&|^".utf8.contains(byte) { kind = .operator; try context.charge(.workUnits); index += 1 }
                else { throw try failure("SV_LEX_INVALID_CHARACTER", start..<(start + 1), source: source) }
            }
            guard tokens.count < maximumTokens - 1 else { throw .invalidInput("Token capacity exhausted before EOF") }
            try context.charge(.expansion)
            tokens.append(SystemVerilogLexicalToken(kind: kind, byteRange: start..<index))
        }
        try context.charge(.expansion)
        tokens.append(SystemVerilogLexicalToken(kind: .endOfFile, byteRange: bytes.count..<bytes.count))
        return tokens
    }

    @available(macOS 26.0, *)
    private func scanNumber(_ bytes: borrowing Span<UInt8>, index: inout Int,
                            context: inout LogicKernelContext) throws(LogicKernelError) {
        let startsWithQuote = bytes[index] == 39
        if !startsWithQuote {
            repeat { try context.charge(.workUnits); index += 1 }
            while index < bytes.count && (Self.isDigit(bytes[index]) || bytes[index] == 95)
        }
        guard index < bytes.count, bytes[index] == 39 else { return }
        try context.charge(.workUnits); index += 1
        guard index < bytes.count else { return }
        if startsWithQuote && (bytes[index] == 48 || bytes[index] == 49 || Self.isUnknownDigit(bytes[index])) {
            // Unbased literals have exactly one digit; their following '?' is conditional.
            try context.charge(.workUnits); index += 1; return
        }
        if bytes[index] == 115 || bytes[index] == 83 {
            try context.charge(.workUnits); index += 1
        }
        guard index < bytes.count, Self.isLetter(bytes[index]) else { return }
        let base = bytes[index] | 32
        try context.charge(.workUnits); index += 1
        if base == 100 {
            if index < bytes.count && (Self.isUnknownDigit(bytes[index]) || bytes[index] == 63) {
                try context.charge(.workUnits); index += 1
                while index < bytes.count && bytes[index] == 95 { try context.charge(.workUnits); index += 1 }
            } else {
                while index < bytes.count && (Self.isDigit(bytes[index]) || bytes[index] == 95) {
                    try context.charge(.workUnits); index += 1
                }
            }
        } else {
            while index < bytes.count && (Self.isLetter(bytes[index]) || Self.isDigit(bytes[index])
                    || bytes[index] == 95 || bytes[index] == 63) {
                try context.charge(.workUnits); index += 1
            }
        }
    }

    private func failure(_ code: String, _ range: Range<Int>, source: borrowing SystemVerilogSourceText)
        throws(LogicKernelError) -> LogicKernelError {
        .sourceFailure(code: .trusted(code), source: try source.origin(for: range), message: "Invalid SystemVerilog lexical input")
    }
    private static func isSpace(_ byte: UInt8) -> Bool { byte == 32 || (9...13).contains(byte) }
    private static func isLetter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
    private static func isDigit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }
    private static func isUnknownDigit(_ byte: UInt8) -> Bool { byte == 88 || byte == 120 || byte == 90 || byte == 122 }
    private static func isIdentifierByte(_ byte: UInt8) -> Bool { isLetter(byte) || isDigit(byte) || byte == 95 || byte == 36 }
}
