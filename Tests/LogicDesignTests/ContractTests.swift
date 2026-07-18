import Foundation
import Testing
@testable import LogicIR
@testable import SystemVerilogFrontend
@testable import PowerIntent
import CircuiteFoundation

@Suite("LogicDesign contract")
struct ContractTests {
    @Test("artifact locator rejects an invalid workspace-relative path")
    func artifactLocatorRejectsInvalidPath() {
        #expect(throws: ArtifactLocationError.self) {
            try ArtifactLocator(path: "../top.sv", kind: .rtl, format: .systemVerilog)
        }
    }

    @Test("invalid domain diagnostic codes become structured diagnostics")
    func invalidDiagnosticCodeIsStructured() {
        let diagnostic = LogicDiagnostic(
            severity: .error,
            code: " invalid-code",
            message: "The producer returned an invalid code."
        ).engineDiagnostic

        #expect(diagnostic.code.rawValue == "logic.invalid-diagnostic-code")
        #expect(diagnostic.detail?.contains(" invalid-code") == true)
    }

    @Test("requests preserve the shared JSON contract")
    func requestRoundTrip() throws {
        let request = LogicElaborationRequest(
            runID: "run-round-trip",
            inputs: [try ArtifactLocator(path: "top.sv", kind: .rtl, format: .systemVerilog)],
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
            artifact: ArtifactReference(
                locator: try ArtifactLocator(path: "design.json", kind: .netlist, format: .json),
                digest: try ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: String(repeating: "1", count: 64)
                ),
                byteCount: 128
            ),
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
    func provenanceValidationRejectsMismatchedInput() throws {
        let reference = LogicDesignReference(
            artifact: ArtifactReference(
                locator: try ArtifactLocator(path: "design.json", kind: .netlist, format: .json),
                digest: try ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: String(repeating: "2", count: 64)
                ),
                byteCount: 128
            ),
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

    @Test("execution contracts conform directly to the shared engine protocol")
    func directEngineConformance() {
        requireEngine(LogicElaboratingEngine.self)
        requireEngine(PowerIntentParsingEngine.self)
    }

    @Test("execution results expose shared evidence capabilities")
    func directResultCapabilities() {
        requireEvidenceResult(LogicElaborationResult.self)
        requireEvidenceResult(PowerIntentParsingResult.self)
    }

    private func requireEngine<T: Engine>(_: T.Type) {}

    private func requireEvidenceResult<T>(_: T.Type)
    where T: ArtifactProducing & DiagnosticReporting & EvidenceProviding {}
}
