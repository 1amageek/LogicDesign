import Foundation
import Testing
@testable import LogicDesign

@Suite("LogicDesign capability report")
struct CapabilityReportTests {
    @Test("current report exposes validation and evidence boundaries")
    func currentReportBoundary() throws {
        let report = LogicDesignCapabilityReport.current

        #expect(report.schemaVersion == LogicDesignCapabilityReport.currentSchemaVersion)
        #expect(report.packageName == "LogicDesign")
        #expect(report.validationChecks.contains("request_contract_validation"))
        #expect(report.evidenceBoundary.producedEvidence.contains("structured_diagnostics"))
        #expect(report.evidenceBoundary.externalDecisions.contains("tool_trust_qualification"))
        #expect(report.blockedSemantics.contains("foundry_process_qualification") == false)

        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any]
        )
        #expect(object["qualification"] == nil)
        #expect(object["package"] == nil)
    }

    @Test("current report round trips")
    func currentReportRoundTrip() throws {
        let report = LogicDesignCapabilityReport.current
        let data = try JSONEncoder().encode(report)

        #expect(try JSONDecoder().decode(LogicDesignCapabilityReport.self, from: data) == report)
    }

    @Test("retained capability fixture matches the current report")
    func retainedCapabilityFixtureMatchesCurrentReport() throws {
        let data = try FixtureCorpusResources.data(at: "Fixtures/capability-report-v2.json")

        #expect(
            try JSONDecoder().decode(LogicDesignCapabilityReport.self, from: data)
                == LogicDesignCapabilityReport.current
        )
    }

    @Test("obsolete schema is rejected")
    func obsoleteSchemaIsRejected() throws {
        let currentData = try JSONEncoder().encode(LogicDesignCapabilityReport.current)
        var object = try #require(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        object["schemaVersion"] = 1
        let obsoleteData = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LogicDesignCapabilityReport.self, from: obsoleteData)
        }
    }

    @Test("legacy qualification field cannot satisfy the current schema")
    func legacyQualificationFieldIsRejected() throws {
        let legacyObject: [String: Any] = [
            "schemaVersion": LogicDesignCapabilityReport.currentSchemaVersion,
            "package": "LogicDesign",
            "implementationVersion": "1",
            "capabilities": [],
            "blockedSemantics": [],
            "qualification": "native subset"
        ]
        let data = try JSONSerialization.data(withJSONObject: legacyObject)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LogicDesignCapabilityReport.self, from: data)
        }
    }
}
