import Foundation
import Testing
@testable import LogicIR
@testable import SystemVerilogFrontend
@testable import PowerIntent
@testable import LogicDesign
import XcircuitePackage

@Suite("LogicDesign contract")
struct ContractTests {
    @Test("contract version starts at one")
    func contractVersion() {
        #expect(LogicDesignAPI.contractVersion == 1)
    }

    @Test("requests preserve the shared JSON contract")
    func requestRoundTrip() throws {
        let request = LogicElaborationRequest(
            runID: "run-round-trip",
            inputs: [XcircuiteFileReference(path: "top.sv", kind: .rtl, format: .systemVerilog)],
            topDesignName: "top",
            sources: [SystemVerilogSourceUnit(path: "top.sv", source: "module top; endmodule")]
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(LogicElaborationRequest.self, from: data)
        #expect(decoded == request)
    }
}
