import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension SystemVerilogSourcePreprocessor {
    mutating func handle(_ directive: Directive, source: borrowing SystemVerilogSourceText, start: Int,
                        content: Range<Int>, output: inout SystemVerilogTextBuffer,
                        context: inout LogicKernelContext) throws(LogicKernelError) {
        try source.withBytes { (bytes: borrowing Span<UInt8>) throws(LogicKernelError) in
            switch directive {
            case .ifdef, .ifndef:
                let name = try readName(content.lowerBound, end: content.upperBound, bytes: bytes, source: source, context: &context)
                try requireEnd(name.range.upperBound, end: content.upperBound, bytes: bytes, source: source, context: &context)
                guard conditionals.count < maximumNesting else {
                    throw try failure(source, start..<content.upperBound, "SV_PP_NESTING", "Conditional nesting exceeds the selected profile")
                }
                let parent = active
                let defined = parent ? try macro(name, context: &context) != nil : false
                let selected = parent && (directive == .ifdef ? defined : !defined)
                try context.charge(.expansion)
                try conditionals.append(Conditional(parentActive: parent, matched: selected, active: selected,
                    origin: source.origin(for: start..<content.upperBound)), receipt: &receipt, bytes: &storageBytes, context: &context)
            case .elsif:
                guard conditionals.count > 0, !conditionals[conditionals.count - 1].sawElse else {
                    throw try failure(source, start..<content.upperBound, "SV_PP_CONDITIONAL_ORDER", "Elsif requires an open conditional before else")
                }
                let name = try readName(content.lowerBound, end: content.upperBound, bytes: bytes, source: source, context: &context)
                try requireEnd(name.range.upperBound, end: content.upperBound, bytes: bytes, source: source, context: &context)
                let last = conditionals.count - 1
                var frame = conditionals[last]
                if frame.parentActive && !frame.matched { frame.active = try macro(name, context: &context) != nil }
                else { frame.active = false }
                frame.matched = frame.matched || frame.active
                conditionals[last] = frame
            case .otherwise:
                try requireEnd(content.lowerBound, end: content.upperBound, bytes: bytes, source: source, context: &context)
                guard conditionals.count > 0, !conditionals[conditionals.count - 1].sawElse else {
                    throw try failure(source, start..<content.upperBound, "SV_PP_CONDITIONAL_ORDER", "Else requires an open conditional without an earlier else")
                }
                let last = conditionals.count - 1
                var frame = conditionals[last]
                frame.active = frame.parentActive && !frame.matched; frame.matched = true; frame.sawElse = true
                conditionals[last] = frame
            case .endif:
                try requireEnd(content.lowerBound, end: content.upperBound, bytes: bytes, source: source, context: &context)
                guard conditionals.count > 0 else {
                    throw try failure(source, start..<content.upperBound, "SV_PP_CONDITIONAL_ORDER", "Endif has no open conditional")
                }
                _ = conditionals.popLast()
            case .define:
                if active { try define(source, content: content, bytes: bytes, context: &context) }
            case .undef:
                if active {
                    let name = try readName(content.lowerBound, end: content.upperBound, bytes: bytes, source: source, context: &context)
                    try requireEnd(name.range.upperBound, end: content.upperBound, bytes: bytes, source: source, context: &context)
                    try undefine(name, context: &context)
                }
            case .undefineall:
                if active {
                    try requireEnd(content.lowerBound, end: content.upperBound, bytes: bytes, source: source, context: &context)
                    for index in macros.indices { try context.charge(.workUnits); macros[index].active = false }
                }
            case .include:
                if active { try include(source, content: content, bytes: bytes, output: &output, context: &context) }
            }
        }
    }

    mutating func define(_ source: borrowing SystemVerilogSourceText, content: Range<Int>, bytes: borrowing Span<UInt8>,
                         context: inout LogicKernelContext) throws(LogicKernelError) {
        let name = try readName(content.lowerBound, end: content.upperBound, bytes: bytes, source: source, context: &context)
        guard try directive(name, context: &context) == nil else {
            throw try failure(source, name.range, "SV_PP_RESERVED_NAME", "Compiler directive names cannot be redefined in this profile")
        }
        var index = name.range.upperBound
        var parameters: Range<Int>?
        if index < content.upperBound && bytes[index] == 40 {
            index += 1; let first = formals.count
            index = try trivia(index, end: content.upperBound, bytes: bytes, source: source, context: &context)
            if index < content.upperBound && bytes[index] == 41 { index += 1 }
            else {
                while true {
                    let formal = try readName(index, end: content.upperBound, bytes: bytes, source: source, context: &context)
                    for previous in first..<formals.count {
                        if try equal(formals[previous], formal, context: &context) {
                            throw try failure(source, formal.range, "SV_PP_DUPLICATE_FORMAL", "Macro formal names must be unique")
                        }
                    }
                    try context.charge(.expansion)
                    try formals.append(formal, receipt: &receipt, bytes: &storageBytes, context: &context)
                    index = try trivia(formal.range.upperBound, end: content.upperBound, bytes: bytes, source: source, context: &context)
                    guard index < content.upperBound else {
                        throw try failure(source, name.range, "SV_PP_FORMAL_LIST", "Macro formal list is not closed")
                    }
                    if bytes[index] == 41 { index += 1; break }
                    guard bytes[index] == 44 else {
                        throw try failure(source, index..<(index + 1), "SV_PP_FORMAL_LIST", "Macro defaults and non-identifier formals are outside the profile")
                    }
                    index += 1
                }
            }
            parameters = first..<formals.count
        }
        try undefine(name, context: &context)
        try context.charge(.expansion)
        try macros.append(Macro(name: name, body: Name(source: copy source, range: index..<content.upperBound), parameters: parameters),
            receipt: &receipt, bytes: &storageBytes, context: &context)
    }

    mutating func include(_ source: borrowing SystemVerilogSourceText, content: Range<Int>, bytes: borrowing Span<UInt8>,
                          output: inout SystemVerilogTextBuffer, context: inout LogicKernelContext) throws(LogicKernelError) {
        var index = try trivia(content.lowerBound, end: content.upperBound, bytes: bytes, source: source, context: &context)
        guard index < content.upperBound && bytes[index] == 34 else {
            throw try failure(source, index..<index, "SV_PP_INCLUDE_NAME", "Include requires a quoted exact bundle logical name")
        }
        index += 1; let begin = index
        while index < content.upperBound && bytes[index] != 34 {
            try context.charge(.workUnits)
            guard bytes[index] != 92 && bytes[index] != 10 && bytes[index] != 13 else {
                throw try failure(source, begin..<index, "SV_PP_INCLUDE_NAME", "Escaped or multiline include names are outside the profile")
            }
            index += 1
        }
        guard index < content.upperBound && index > begin else {
            throw try failure(source, begin..<index, "SV_PP_INCLUDE_NAME", "Include name is empty or not closed")
        }
        let name = Name(source: copy source, range: begin..<index)
        try requireEnd(index + 1, end: content.upperBound, bytes: bytes, source: source, context: &context)
        var selected: Int?
        for ordinal in 0..<bundle.count {
            let document = try bundle.document(at: ordinal)
            if try matches(name, document.logicalName, context: &context) { selected = ordinal; break }
        }
        guard let selected else {
            throw try failure(source, name.range, "SV_PP_INCLUDE_MISSING", "Include logical name is not in the exact source bundle")
        }
        for offset in files.indices {
            try context.charge(.workUnits)
            if files[offset] == selected { throw try failure(source, name.range, "SV_PP_INCLUDE_CYCLE", "Recursive include is outside the preprocessing profile") }
        }
        try file(selected, output: &output, context: &context)
    }
}
