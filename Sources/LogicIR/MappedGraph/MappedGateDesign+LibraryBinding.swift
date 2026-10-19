import CircuiteFoundation
import LogicKernelCore

extension MappedGateDesign {
    @available(macOS 26.0, *)
    public borrowing func validateLibrary(_ library: borrowing LogicTechnologyLibrary,
                                          context: inout LogicKernelContext) throws(LogicKernelError) {
        try context.checkpoint()
        let bound = storage.library
        if bound.sharesStorage(with: library) { return }
        try context.charge(.workUnits, amount: UInt64(bound.source.digest.hexadecimalValue.utf8.count)
            + UInt64(library.source.digest.hexadecimalValue.utf8.count)
            + UInt64(bound.source.digest.algorithm.rawValue.utf8.count)
            + UInt64(library.source.digest.algorithm.rawValue.utf8.count) + 1)
        guard bound.source == library.source, bound.cellCount == library.cellCount else {
            throw .invalidModel("Mapped design library source or cell count differs")
        }
        for index in 0..<bound.cellCount {
            let a = try bound.cell(at: .init(index))
            let b = try library.cell(at: .init(index))
            try context.charge(.workUnits, amount: UInt64(a.name.utf8.count) + UInt64(b.name.utf8.count) + 1)
            guard a.id == b.id, a.name == b.name, a.pinCount == b.pinCount, a.area.bitPattern == b.area.bitPattern else {
                throw .invalidModel("Mapped design cell definition differs")
            }
            for pin in 0..<a.pinCount {
                let left = try a.pin(at: .init(pin)); let right = try b.pin(at: .init(pin))
                try context.charge(.workUnits, amount: UInt64(left.name.utf8.count) + UInt64(right.name.utf8.count) + 1)
                guard left.id == right.id, left.name == right.name, left.direction == right.direction,
                      try Self.sameFunction(left.function, right.function, context: &context) else {
                    throw .invalidModel("Mapped design physical pin or function differs")
                }
            }
            switch (a.state, b.state) {
            case (nil, nil): break
            case (.some(let left), .some(let right)):
                guard left.control == right.control, left.asynchronousReset == right.asynchronousReset,
                      try Self.sameFunction(left.nextState, right.nextState, context: &context) else {
                    throw .invalidModel("Mapped design sequential function or control differs")
                }
            default: throw .invalidModel("Mapped design cell state profile differs")
            }
        }
    }

    @available(macOS 26.0, *)
    private static func sameFunction(_ a: LogicBooleanFunction?, _ b: LogicBooleanFunction?,
                                     context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (.some(let a), .some(let b)):
            try context.charge(.workUnits)
            guard a.inputCount == b.inputCount, a.nodeCount == b.nodeCount, a.output == b.output else { return false }
            return try a.withOperations { left throws(LogicKernelError) in
                try b.withOperations { right throws(LogicKernelError) in
                    for index in left.indices {
                        try context.charge(.workUnits)
                        if left[index] != right[index] { return false }
                    }
                    return true
                }
            }
        default: return false
        }
    }
}
