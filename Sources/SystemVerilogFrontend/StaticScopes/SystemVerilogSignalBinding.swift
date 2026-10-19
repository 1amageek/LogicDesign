import LogicIR

package struct SystemVerilogSignalBinding: Sendable {
    package let declaration: Int
    package let type: SystemVerilogConstantType
    package let signal: RTLSignalIndex
    package init(declaration: Int, type: SystemVerilogConstantType, signal: RTLSignalIndex) {
        self.declaration = declaration; self.type = type; self.signal = signal
    }
}
