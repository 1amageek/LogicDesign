import Foundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public protocol MappedGateVerilogCoding: Sendable {
    func encode(_ design: borrowing MappedGateDesign, top: String) throws -> Data
    func decode(_ data: Data, identities: borrowing MappedGateDesign, top: String,
                context: inout LogicKernelContext) throws -> MappedGateDesign
    func encode(_ design: borrowing MappedGateDesign, top: String, naming: borrowing MappedGateVerilogNaming,
                context: inout LogicKernelContext) throws -> Data
    func decode(_ data: Data, identities: borrowing MappedGateDesign, top: String,
                naming: borrowing MappedGateVerilogNaming,
                context: inout LogicKernelContext) throws -> MappedGateDesign
}

@available(macOS 26.0, *)
extension MappedGateVerilogCoding {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Older external conformers have no named export.
    // Callers invoking this requirement receive unsupported until that conformer implements
    // exact identity-bound naming, standard escaping, and bounded output admission.
    public func encode(_ design: borrowing MappedGateDesign, top: String,
                       naming: borrowing MappedGateVerilogNaming,
                       context: inout LogicKernelContext) throws -> Data {
        throw LogicKernelError.unsupported("This codec does not implement identity-bound Verilog naming")
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Older external conformers have no named import.
    // Callers invoking this requirement receive unsupported until that conformer reads
    // actual named connectivity and validates complete identities under the shared budget.
    public func decode(_ data: Data, identities: borrowing MappedGateDesign, top: String,
                       naming: borrowing MappedGateVerilogNaming,
                       context: inout LogicKernelContext) throws -> MappedGateDesign {
        throw LogicKernelError.unsupported("This codec does not implement identity-bound Verilog naming")
    }
}
