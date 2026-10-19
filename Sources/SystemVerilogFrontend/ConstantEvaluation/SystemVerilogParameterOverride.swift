package struct SystemVerilogParameterOverride: Sendable {
    package let declaration: Int
    internal let bindings: SystemVerilogParameterBindings
    package let expression: SystemVerilogConstantExpression
    package init(declaration: Int, in bindings: SystemVerilogParameterBindings, expression: SystemVerilogConstantExpression) {
        self.declaration = declaration; self.bindings = bindings; self.expression = expression
    }
}
