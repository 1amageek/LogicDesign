import LogicIR

package struct SystemVerilogSignalBinding: Sendable {
    package let declaration: Int
    package let type: SystemVerilogConstantType
    package let signal: RTLSignalIndex
    package let valueDomain: RTLResolvedSignal.ValueDomain
    package let storage: RTLResolvedSignal.StorageKind
    package init(declaration: Int, type: SystemVerilogConstantType, signal: RTLSignalIndex,
                 valueDomain: RTLResolvedSignal.ValueDomain = .fourState, storage: RTLResolvedSignal.StorageKind = .variable) {
        self.declaration = declaration; self.type = type; self.signal = signal
        self.valueDomain = valueDomain; self.storage = storage
    }
}
