import Foundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public protocol BitLogicDesignControlledCoding: BitLogicDesignCoding {
    func encodeControlled(_ design: borrowing BitLogicDesign, context: inout LogicKernelContext)
        throws -> (value: Data, retention: LogicKernelRetention)
    func decodeControlled(_ data: Data, context: inout LogicKernelContext)
        throws -> (value: BitLogicDesign, retention: LogicKernelRetention)
}
