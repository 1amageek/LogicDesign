import Foundation

/// The mapped and source-only profiles share exact lexical boundaries.
struct MappedGateVerilogLexer {
    struct Token {
        let value: String
        let escaped: Bool
        let byteRange: Range<Int>
    }
    struct Failure: Error { let byteRange: Range<Int> }

    static func tokenize(_ text: String) throws(Failure) -> [Token] {
        let chars = Array(text.utf8)
        var i = 0
        var result: [Token] = []
        result.reserveCapacity(chars.count)
        func punctuation(_ value: UInt8) -> Bool {
            value == 40 || value == 41 || value == 44 || value == 46 || value == 59 || value == 61
        }
        while i < chars.count {
            if chars[i] <= 32 { i += 1; continue }
            if chars[i] == 92 {
                let opening = i
                i += 1; let start = i
                while i < chars.count && chars[i] > 32 { i += 1 }
                guard i > start, i < chars.count else { throw Failure(byteRange: opening..<i) }
                result.append(.init(value: String(decoding: chars[start..<i], as: UTF8.self),
                                    escaped: true, byteRange: opening..<i))
                continue
            }
            if punctuation(chars[i]) {
                result.append(.init(value: String(UnicodeScalar(chars[i])), escaped: false, byteRange: i..<(i + 1)))
                i += 1; continue
            }
            let start = i
            while i < chars.count && chars[i] > 32 && !punctuation(chars[i]) { i += 1 }
            result.append(.init(value: String(decoding: chars[start..<i], as: UTF8.self),
                                escaped: false, byteRange: start..<i))
        }
        return result
    }
}
