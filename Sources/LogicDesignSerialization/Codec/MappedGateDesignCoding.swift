import Foundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public protocol MappedGateDesignCoding: Sendable {
    func encode(_ design: borrowing MappedGateDesign) throws -> Data
    func decode(_ data: Data, library: borrowing LogicTechnologyLibrary,
                context: inout LogicKernelContext) throws -> MappedGateDesign
}
