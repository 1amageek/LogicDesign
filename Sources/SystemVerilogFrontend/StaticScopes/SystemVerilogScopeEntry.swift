import LogicKernelCore

internal struct SystemVerilogScopeEntry: Sendable {
    let symbol: Int
    let declaration: Int
    var value: SystemVerilogConstant?
    let isGenerateConstant: Bool

    init(symbol: Int, declaration: Int, value: SystemVerilogConstant?, isGenerateConstant: Bool = false) {
        self.symbol = symbol; self.declaration = declaration; self.value = value
        self.isGenerateConstant = isGenerateConstant
    }
}
