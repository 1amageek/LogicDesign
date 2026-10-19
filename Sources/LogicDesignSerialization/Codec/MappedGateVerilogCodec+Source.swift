import Foundation
import LogicKernelCore

@available(macOS 26.0, *)
extension MappedGateVerilogCodec: StructuralVerilogSourceDecoding {
    public func decodeSource(_ data: Data, top: String, context: inout LogicKernelContext)
        throws(StructuralVerilogSourceError) -> StructuralVerilogSource {
        typealias Parser = StructuralVerilogSourceParser
        try Parser.charge(.expansion, UInt64(data.count), context: &context)
        // UTF-8 validation, lexical scans, and token string copies are linear in source bytes.
        try Parser.charge(.workUnits, try Parser.product(data.count, 4), context: &context)
        let lexicalBytes = try Parser.add(Parser.product(data.count, MemoryLayout<MappedGateVerilogLexer.Token>.stride + 3),
                                         UInt64(MemoryLayout<String>.stride + MemoryLayout<[UInt8]>.stride
                                                + MemoryLayout<[MappedGateVerilogLexer.Token]>.stride))
        let lexical = try Parser.reserve(lexicalBytes, context: &context)
        let result: StructuralVerilogSource
        do throws(StructuralVerilogSourceError) {
            for (index, byte) in data.enumerated() {
                guard byte >= 32 || (byte >= 9 && byte <= 13) else {
                    throw StructuralVerilogSourceError.unsupported(byteRange: index..<(index + 1),
                        semantic: "Control byte is not structural whitespace")
                }
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw StructuralVerilogSourceError.malformed(byteRange: 0..<data.count, reason: "Source is not UTF-8")
            }
            let tokens: [MappedGateVerilogLexer.Token]
            do { tokens = try MappedGateVerilogLexer.tokenize(text) }
            catch { throw StructuralVerilogSourceError.malformed(byteRange: error.byteRange, reason: "Unterminated escaped identifier") }
            let tables = try Parser.reserve(Parser.tableBytes(tokens.count), context: &context)
            do throws(StructuralVerilogSourceError) {
                var parser = Parser(tokens: tokens, byteCount: data.count)
                let module = try parser.parse(top: top, context: &context)
                result = try parser.finish(module: module, context: &context)
            } catch {
                try Parser.release(consume tables, context: &context); throw error
            }
            try Parser.release(consume tables, context: &context)
        } catch {
            try Parser.release(consume lexical, context: &context); throw error
        }
        try Parser.release(consume lexical, context: &context)
        return result
    }
}
