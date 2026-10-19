import CircuiteFoundation
import LogicKernelCore

@available(macOS 26.0, *)
public struct NativeMappedGateRealizationValidator: MappedGateRealizationValidating {
    public init() {}

    public func validate(_ design: borrowing MappedGateDesign, policy: MappedGateRealizationPolicy,
                         context: inout LogicKernelContext) throws(LogicKernelError) {
        try context.checkpoint()
        try design.withTables { nets, instances, _, _, _, _ throws(LogicKernelError) in
            for index in instances.indices {
                try context.charge(.workUnits)
                try instances[index].requirePhysicalStartupRealization()
            }
            if case .physicalCells = policy {
                for index in nets.indices {
                    try context.charge(.workUnits)
                    if case .constant(let value) = nets[index].driver {
                        throw .unsupported("Mapped net \(nets[index].id.rawValue) requires an actual tie-cell output for constant \(value ? 1 : 0)")
                    }
                }
            }
        }
    }
}
