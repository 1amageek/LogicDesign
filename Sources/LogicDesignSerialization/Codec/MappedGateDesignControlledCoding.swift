import Foundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public protocol MappedGateDesignControlledCoding: MappedGateDesignCoding {
    func encodeControlled(_ design: borrowing MappedGateDesign, context: inout LogicKernelContext)
        throws -> (value: Data, retention: LogicKernelRetention)
    func decodeControlled(_ data: Data, library: borrowing LogicTechnologyLibrary, context: inout LogicKernelContext)
        throws -> (value: MappedGateDesign, retention: LogicKernelRetention)
}
