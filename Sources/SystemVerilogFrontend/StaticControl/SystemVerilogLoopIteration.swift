import LogicIR

package struct SystemVerilogLoopIteration: Sendable {
    internal final class Identity: Sendable {}
    internal let identity: Identity
    package let body: Int
    package let declaration: Int
    package let scope: SystemVerilogConstantScope
    package let value: LogicFourStateVector
}
