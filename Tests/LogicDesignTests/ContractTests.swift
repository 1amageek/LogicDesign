import Foundation
import Testing
@testable import LogicIR
@testable import SystemVerilogFrontend
@testable import PowerIntent
@testable import LogicDesign
import CircuiteFoundation

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
            inputs: [ArtifactLocator(path: "top.sv", kind: .rtl, format: .systemVerilog)],
            topDesignName: "top",
            sources: [SystemVerilogSourceUnit(path: "top.sv", source: "module top; endmodule")]
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(LogicElaborationRequest.self, from: data)
        #expect(decoded == request)
    }

    @Test("design references preserve canonical transformation provenance")
    func designReferenceProvenanceRoundTrip() throws {
        let provenance = LogicDesignProvenance(
            sourceDesignDigest: "source-design",
            inputDesignDigest: "input-design",
            transformationID: "native-lowering",
            producerID: "LogicLowering",
            producerVersion: "1",
            runID: "run-provenance"
        )
        let reference = LogicDesignReference(
            artifact: ArtifactLocator(path: "design.json", kind: .netlist, format: .json),
            topDesignName: "top",
            designDigest: "output-design",
            provenance: provenance
        )

        let data = try JSONEncoder().encode(reference)
        let decoded = try JSONDecoder().decode(LogicDesignReference.self, from: data)

        #expect(decoded == reference)
        #expect(decoded.provenance?.isValid == true)
    }

    @Test("provenance validation rejects mismatched transformed input")
    func provenanceValidationRejectsMismatchedInput() {
        let reference = LogicDesignReference(
            artifact: ArtifactLocator(path: "design.json", kind: .netlist, format: .json),
            topDesignName: "top",
            designDigest: "current",
            provenance: LogicDesignProvenance(
                sourceDesignDigest: "source",
                inputDesignDigest: "other",
                transformationID: "transform",
                producerID: "producer",
                producerVersion: "1.0.0"
            )
        )

        let issues = LogicDesignProvenanceValidation.issues(for: reference)

        #expect(issues.contains { $0.code == "design_provenance_input_digest_mismatch" })
    }
}
