import CircuiteFoundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
package struct SystemVerilogSourcePreprocessor: ~Copyable {
    struct Name { let source: SystemVerilogSourceText; let range: Range<Int> }
    struct Macro { let name: Name; let body: Name; let parameters: Range<Int>?; var active = true }
    struct Conditional {
        let parentActive: Bool
        var matched: Bool
        var active: Bool
        var sawElse = false
        let origin: LogicKernelSourceRange
    }
    enum Directive: Equatable { case define, undef, undefineall, include, ifdef, ifndef, elsif, otherwise, endif }

    let bundle: LogicSourceBundle
    let maximumNesting: Int
    var receipt: LogicStorageReservation
    var storageBytes: UInt64 = 0
    var macros = SystemVerilogPreprocessingBuffer<Macro>()
    var formals = SystemVerilogPreprocessingBuffer<Name>()
    var conditionals = SystemVerilogPreprocessingBuffer<Conditional>()
    var arguments = SystemVerilogPreprocessingBuffer<Name>()
    var delimiters = SystemVerilogPreprocessingBuffer<UInt8>()
    var files = SystemVerilogPreprocessingBuffer<Int>()
    var expansions = SystemVerilogPreprocessingBuffer<Int>()
    var outputs = SystemVerilogPreprocessingBuffer<SystemVerilogSourceText>()
    var depth = 0
    var active: Bool { conditionals.count == 0 || conditionals[conditionals.count - 1].active }

    package static func preprocess(_ bundle: borrowing LogicSourceBundle, roots: borrowing [String],
        maximumNesting: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> [SystemVerilogSourceText] {
        guard !roots.isEmpty, maximumNesting > 0 else { throw .invalidInput("Invalid preprocessing roots or nesting limit") }
        var run = Self(bundle: copy bundle, maximumNesting: maximumNesting,
            receipt: try context.reserveStorage(byteCount: 0))
        let result: [SystemVerilogSourceText]
        do throws(LogicKernelError) {
            for index in roots.indices {
                try context.charge(.workUnits, amount: UInt64(roots[index].utf8.count) + 1)
                guard !roots[index].isEmpty else { throw .invalidInput("Compilation root name is empty") }
                for previous in 0..<index {
                    try context.charge(.workUnits, amount: UInt64(roots[previous].utf8.count) + 1)
                    guard !roots[previous].utf8.elementsEqual(roots[index].utf8) else {
                        throw .invalidInput("Compilation root is duplicated")
                    }
                }
                var selected: Int?
                for document in 0..<bundle.count {
                    let source = try bundle.document(at: document)
                    try context.charge(.workUnits, amount: UInt64(source.logicalName.utf8.count) + 1)
                    if source.logicalName.utf8.elementsEqual(roots[index].utf8) { selected = document; break }
                }
                guard let selected else { throw .invalidInput("Compilation root is not present in the exact source bundle") }
                let root = try bundle.document(at: selected)
                var buffer = try SystemVerilogTextBuffer(context: &context)
                do throws(LogicKernelError) { try run.file(selected, output: &buffer, context: &context) }
                catch { try buffer.release(context: &context); throw error }
                let end = UInt64(root.byteCount)
                let text = try buffer.finish(root: root,
                    terminalOrigin: LogicKernelSourceRange(artifactID: root.artifactID, byteRange: end..<end), context: &context)
                try context.charge(.outputBytes, amount: UInt64(text.byteCount))
                try run.outputs.append(text, receipt: &run.receipt, bytes: &run.storageBytes, context: &context)
            }
            guard run.conditionals.count == 0 else {
                throw .sourceFailure(code: .trusted("SV_PP_UNCLOSED_CONDITIONAL"), source: run.conditionals[0].origin,
                    message: "Conditional directives must balance in the compilation unit")
            }
            let size = UInt64(run.outputs.count).multipliedReportingOverflow(by: UInt64(MemoryLayout<SystemVerilogSourceText>.stride))
            guard !size.overflow else { throw .invalidInput("Preprocessed root storage overflow") }
            _ = try context.reserveStorage(byteCount: size.partialValue)
            result = run.outputs.values
        } catch { try context.releaseStorage(run.receipt); throw error }
        try context.releaseStorage(run.receipt)
        return result
    }

    mutating func file(_ index: Int, output: inout SystemVerilogTextBuffer,
                       context: inout LogicKernelContext) throws(LogicKernelError) {
        let source = SystemVerilogSourceText(try bundle.document(at: index))
        for offset in files.indices {
            try context.charge(.workUnits)
            if files[offset] == index { throw try failure(source, 0..<0, "SV_PP_INCLUDE_CYCLE", "Recursive include is outside the preprocessing profile") }
        }
        try files.append(index, receipt: &receipt, bytes: &storageBytes, context: &context)
        defer { _ = files.popLast() }
        _ = try scan(source, range: 0..<source.byteCount, directivesAllowed: true, output: &output, context: &context)
    }

    func failure(_ source: borrowing SystemVerilogSourceText, _ range: Range<Int>, _ code: String,
                 _ message: String) throws(LogicKernelError) -> LogicKernelError {
        .sourceFailure(code: .trusted(code), source: try source.origin(for: range), message: message)
    }

    static func isNameStart(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) || byte == 95 }
    static func isNameByte(_ byte: UInt8) -> Bool { isNameStart(byte) || (48...57).contains(byte) || byte == 36 }
    static func isSpace(_ byte: UInt8) -> Bool { byte == 32 || (9...13).contains(byte) }

    func equal(_ a: borrowing Name, _ b: borrowing Name, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        try context.charge(.workUnits)
        guard a.range.count == b.range.count else { return false }
        return try a.source.withBytes { (left: borrowing Span<UInt8>) throws(LogicKernelError) in
            try b.source.withBytes { (right: borrowing Span<UInt8>) throws(LogicKernelError) in
                for offset in 0..<a.range.count {
                    try context.charge(.workUnits)
                    if left[a.range.lowerBound + offset] != right[b.range.lowerBound + offset] { return false }
                }
                return true
            }
        }
    }

    func matches(_ name: borrowing Name, _ spelling: String,
                 context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        try context.charge(.workUnits)
        guard name.range.count == spelling.utf8.count else { return false }
        return try name.source.withBytes { (bytes: borrowing Span<UInt8>) throws(LogicKernelError) in
            var index = name.range.lowerBound
            for byte in spelling.utf8 {
                try context.charge(.workUnits)
                if bytes[index] != byte { return false }; index += 1
            }
            return true
        }
    }

    func macro(_ name: borrowing Name, context: inout LogicKernelContext) throws(LogicKernelError) -> Int? {
        for index in macros.indices.reversed() {
            try context.charge(.workUnits)
            if macros[index].active, try equal(macros[index].name, name, context: &context) { return index }
        }
        return nil
    }

    mutating func undefine(_ name: borrowing Name, context: inout LogicKernelContext) throws(LogicKernelError) {
        for index in macros.indices {
            try context.charge(.workUnits)
            if macros[index].active, try equal(macros[index].name, name, context: &context) { macros[index].active = false }
        }
    }

    func directive(_ name: borrowing Name, context: inout LogicKernelContext) throws(LogicKernelError) -> Directive? {
        if try matches(name, "define", context: &context) { return .define }
        if try matches(name, "undef", context: &context) { return .undef }
        if try matches(name, "undefineall", context: &context) { return .undefineall }
        if try matches(name, "include", context: &context) { return .include }
        if try matches(name, "ifdef", context: &context) { return .ifdef }
        if try matches(name, "ifndef", context: &context) { return .ifndef }
        if try matches(name, "elsif", context: &context) { return .elsif }
        if try matches(name, "else", context: &context) { return .otherwise }
        if try matches(name, "endif", context: &context) { return .endif }
        return nil
    }
}
