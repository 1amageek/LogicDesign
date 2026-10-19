import LogicKernelCore

@available(macOS 26.0, *)
public protocol MappedGateRealizationValidating: Sendable {
    func validate(_ design: borrowing MappedGateDesign, policy: MappedGateRealizationPolicy,
                  context: inout LogicKernelContext) throws(LogicKernelError)
}
