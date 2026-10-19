import LogicIR
import LogicKernelCore

public struct NativeSystemVerilogElaborator: SystemVerilogElaborating {
    public init() {}

    @available(macOS 26.0, *)
    public func elaborate(_ sources: borrowing LogicSourceBundle, options: borrowing SystemVerilogElaborationOptions,
                          context: inout LogicKernelContext) throws(LogicKernelError) -> ElaboratedRTL {
        try context.checkpoint()
        let roots = try SystemVerilogSourcePreprocessor.preprocess(sources, roots: options.roots,
            maximumNesting: options.maximumNesting, context: &context)
        var buffer = try SystemVerilogTextBuffer(context: &context)
        do throws(LogicKernelError) {
            for index in roots.indices {
                try context.charge(.workUnits)
                let text = roots[index]
                try buffer.append(text, range: 0..<text.byteCount, context: &context)
                if text.root.byteCount > 0 {
                    let last = UInt64(text.root.byteCount)
                    try buffer.appendSeparator(anchor: (text.root, LogicKernelSourceRange(
                        artifactID: text.root.artifactID, byteRange: (last - 1)..<last)), context: &context)
                }
            }
        } catch { try buffer.release(context: &context); throw error }
        let finalRoot = roots[roots.count - 1].root
        let end = UInt64(finalRoot.byteCount)
        let unit = try buffer.finish(root: roots[0].root, terminalOrigin: LogicKernelSourceRange(
            artifactID: finalRoot.artifactID, byteRange: end..<end), context: &context)
        let tokens = try SystemVerilogByteLexer().tokenize(unit, maximumTokens: options.maximumTokens, context: &context)
        let syntax = try SystemVerilogSyntaxParser.parse(tokens, limits: options.syntax, context: &context)
        let scratch = try context.reserveStorage(byteCount: UInt64(MemoryLayout<SystemVerilogSyntaxTree>.stride))
        let result: ElaboratedRTL
        do throws(LogicKernelError) {
            result = try SystemVerilogProgramCompiler.compile([syntax], top: options.top, capacity: options.rtl,
                maximumNesting: options.maximumNesting, context: &context)
        } catch { try context.releaseStorage(scratch); throw error }
        try context.releaseStorage(scratch)
        return result
    }
}
