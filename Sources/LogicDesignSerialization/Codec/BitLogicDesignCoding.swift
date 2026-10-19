import Foundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public protocol BitLogicDesignCoding: Sendable {
    func encode(_ design: borrowing BitLogicDesign) throws -> Data
    func decode(_ data: Data, context: inout LogicKernelContext) throws -> BitLogicDesign
}
