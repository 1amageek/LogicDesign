import LogicIR
import LogicKernelCore

public struct SystemVerilogElaborationOptions: Sendable {
    public static let profileIdentifier = "systemverilog.synthesis.v1"
    public let roots: [String]
    public let top: String
    public let maximumTokens: Int
    public let syntax: SystemVerilogSyntaxLimits
    public let rtl: RTLResolvedCapacity
    public let maximumNesting: Int

    public init(roots: consuming [String], top: String, maximumTokens: Int, syntax: SystemVerilogSyntaxLimits,
                rtl: RTLResolvedCapacity, maximumNesting: Int) throws(LogicKernelError) {
        guard !roots.isEmpty, !top.isEmpty, maximumTokens > 0, maximumNesting > 0 else {
            throw .invalidInput("Elaboration requires roots, top and positive token/nesting capacities")
        }
        self.roots = roots; self.top = top; self.maximumTokens = maximumTokens
        self.syntax = syntax; self.rtl = rtl; self.maximumNesting = maximumNesting
    }
}
