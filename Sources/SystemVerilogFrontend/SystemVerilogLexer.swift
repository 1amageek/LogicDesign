import Foundation
import LogicIR
import CircuiteFoundation

public struct SystemVerilogLexer: SystemVerilogLexing {
    private static let keywords: Set<String> = [
        "always", "always_comb", "always_ff", "always_latch", "assign", "begin", "case", "casex",
        "casez", "default", "else", "end", "endcase", "endmodule", "endgenerate", "for", "generate",
        "genvar", "if", "inout", "input", "integer", "localparam", "logic", "module", "negedge",
        "output", "parameter", "posedge", "reg", "wire", "while"
    ]

    public init() {}

    public func lex(_ source: SystemVerilogSourceUnit) -> SystemVerilogLexResult {
        let characters = Array(source.source)
        var index = 0
        var line = 1
        var column = 1
        var tokens: [SystemVerilogToken] = []
        var diagnostics: [LogicDiagnostic] = []

        func location() -> LogicSourceLocation {
            LogicSourceLocation(path: source.path, line: line, column: column, offset: index)
        }

        func advance() -> Character? {
            guard index < characters.count else { return nil }
            let character = characters[index]
            index += 1
            if character == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
            return character
        }

        func peek(_ offset: Int = 0) -> Character? {
            let position = index + offset
            guard position < characters.count else { return nil }
            return characters[position]
        }

        func makeSpan(from start: LogicSourceLocation) -> LogicSourceSpan {
            LogicSourceSpan(start: start, end: location())
        }

        while index < characters.count {
            guard let character = peek() else { break }
            if character.isWhitespace {
                _ = advance()
                continue
            }
            if character == "/", peek(1) == "/" {
                _ = advance()
                _ = advance()
                while let next = peek(), next != "\n" { _ = advance() }
                continue
            }
            if character == "/", peek(1) == "*" {
                let start = location()
                _ = advance()
                _ = advance()
                var closed = false
                while let next = peek() {
                    if next == "*", peek(1) == "/" {
                        _ = advance()
                        _ = advance()
                        closed = true
                        break
                    }
                    _ = advance()
                }
                if !closed {
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "SV_LEX_UNTERMINATED_COMMENT",
                        message: "The block comment is not terminated.",
                        location: LogicSourceSpan(start: start, end: location()),
                        suggestedActions: ["close_block_comment"]
                    ))
                }
                continue
            }

            let start = location()
            if character == "\"" {
                _ = advance()
                var value = ""
                var terminated = false
                while let next = peek() {
                    _ = advance()
                    if next == "\"" {
                        terminated = true
                        break
                    }
                    if next == "\\", let escaped = peek() {
                        value.append(next)
                        value.append(escaped)
                        _ = advance()
                    } else {
                        value.append(next)
                    }
                }
                tokens.append(SystemVerilogToken(kind: .string, lexeme: value, span: makeSpan(from: start)))
                if !terminated {
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "SV_LEX_UNTERMINATED_STRING",
                        message: "The string literal is not terminated.",
                        location: makeSpan(from: start),
                        suggestedActions: ["close_string_literal"]
                    ))
                }
                continue
            }

            if character == "\\" {
                _ = advance()
                var value = "\\"
                while let next = peek(), !next.isWhitespace {
                    value.append(next)
                    _ = advance()
                }
                tokens.append(SystemVerilogToken(kind: .identifier, lexeme: value, span: makeSpan(from: start)))
                continue
            }

            if character.isLetter || character == "_" || character == "$" {
                var value = ""
                while let next = peek(), next.isLetter || next.isNumber || next == "_" || next == "$" {
                    value.append(next)
                    _ = advance()
                }
                let kind: SystemVerilogTokenKind = Self.keywords.contains(value) ? .keyword : .identifier
                tokens.append(SystemVerilogToken(kind: kind, lexeme: value, span: makeSpan(from: start)))
                continue
            }

            if character.isNumber || character == "'" {
                var value = ""
                while let next = peek(), next.isLetter || next.isNumber || next == "_" || next == "'" || next == "?" {
                    value.append(next)
                    _ = advance()
                }
                tokens.append(SystemVerilogToken(kind: .number, lexeme: value, span: makeSpan(from: start)))
                continue
            }

            let multiCharacterOperators = ["===", "!==", "<<<", ">>>", "&&&", "<=", ">=", "==", "!=", "&&", "||", "<<", ">>", "=>", ":=", "++", "--", "+=", "-=", "**", "->"]
            var matchedOperator: String?
            for length in stride(from: 3, through: 2, by: -1) {
                let candidate = String(characters[index..<min(index + length, characters.count)])
                if multiCharacterOperators.contains(candidate) {
                    matchedOperator = candidate
                    break
                }
            }
            if let matchedOperator {
                for _ in matchedOperator { _ = advance() }
                tokens.append(SystemVerilogToken(kind: .operator, lexeme: matchedOperator, span: makeSpan(from: start)))
                continue
            }

            if "()[]{};,:.@#?`".contains(character) {
                _ = advance()
                tokens.append(SystemVerilogToken(kind: .symbol, lexeme: String(character), span: makeSpan(from: start)))
                continue
            }
            if "+-*/%<>=!~&|^".contains(character) {
                _ = advance()
                tokens.append(SystemVerilogToken(kind: .operator, lexeme: String(character), span: makeSpan(from: start)))
                continue
            }

            _ = advance()
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "SV_LEX_INVALID_CHARACTER",
                message: "The source contains an unsupported character.",
                entity: String(character),
                location: makeSpan(from: start),
                suggestedActions: ["remove_invalid_character"]
            ))
        }

        let eof = LogicSourceLocation(path: source.path, line: line, column: column, offset: index)
        tokens.append(SystemVerilogToken(
            kind: .endOfFile,
            lexeme: "",
            span: LogicSourceSpan(start: eof, end: eof)
        ))
        return SystemVerilogLexResult(tokens: tokens, diagnostics: diagnostics)
    }
}
