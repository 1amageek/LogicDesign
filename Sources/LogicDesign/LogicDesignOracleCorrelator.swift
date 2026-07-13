import Foundation
import LogicIR
import SystemVerilogFrontend
import CircuiteFoundation

public enum LogicDesignOracleCorrelator {
    public static func validate(_ manifest: LogicDesignOracleManifest) throws {
        guard manifest.schemaVersion == LogicDesignOracleManifest.currentSchemaVersion else {
            throw LogicDesignOracleCorrelationError.unsupportedManifestSchema(manifest.schemaVersion)
        }

        var identifiers = Set<String>()
        for oracleCase in manifest.cases {
            guard identifiers.insert(oracleCase.id).inserted else {
                throw LogicDesignOracleCorrelationError.duplicateCaseID(oracleCase.id)
            }
            guard !oracleCase.id.isEmpty,
                  !oracleCase.sourcePath.isEmpty,
                  !oracleCase.topDesignName.isEmpty,
                  isSHA256(oracleCase.sourceSHA256),
                  oracleCase.expectedStatus == "completed"
                    || oracleCase.expectedStatus == "failed"
                    || oracleCase.expectedStatus == "blocked"
                    || oracleCase.expectedStatus == "cancelled" else {
                throw LogicDesignOracleCorrelationError.invalidCase(oracleCase.id)
            }
            if let digest = oracleCase.expectedSnapshotDigest, !isSHA256(digest) {
                throw LogicDesignOracleCorrelationError.invalidCase(
                    "\(oracleCase.id) has an invalid snapshot digest"
                )
            }
        }
    }

    public static func correlate(
        manifest: LogicDesignOracleManifest,
        oracleCase: LogicDesignOracleCase,
        sourceSHA256: String,
        topDesignName: String,
        result: LogicElaborationResult
    ) throws -> LogicDesignOracleCorrelation {
        try validate(manifest)
        guard manifest.caseWithID(oracleCase.id) != nil else {
            throw LogicDesignOracleCorrelationError.caseNotFound(oracleCase.id)
        }
        guard sourceSHA256 == oracleCase.sourceSHA256 else {
            throw LogicDesignOracleCorrelationError.sourceDigestMismatch(
                expected: oracleCase.sourceSHA256,
                actual: sourceSHA256
            )
        }

        let snapshotDigest: String?
        if let snapshot = result.payload.snapshot {
            snapshotDigest = try LogicDesignSnapshotCodec.digest(snapshot)
        } else {
            snapshotDigest = nil
        }
        let observation = LogicDesignOracleObservation(
            caseID: oracleCase.id,
            sourceSHA256: sourceSHA256,
            topDesignName: topDesignName,
            status: result.status.rawValue,
            snapshotDigest: snapshotDigest,
            diagnosticCodes: result.diagnostics.map(\.code),
            implementationID: result.metadata.implementationID,
            implementationVersion: result.metadata.implementationVersion
        )

        var mismatches: [LogicDesignOracleMismatch] = []
        appendMismatch(
            field: "topDesignName",
            expected: oracleCase.topDesignName,
            actual: observation.topDesignName,
            to: &mismatches
        )
        appendMismatch(
            field: "status",
            expected: oracleCase.expectedStatus,
            actual: observation.status,
            to: &mismatches
        )
        if oracleCase.expectedSnapshotDigest != nil {
            appendMismatch(
                field: "snapshotDigest",
                expected: oracleCase.expectedSnapshotDigest,
                actual: observation.snapshotDigest,
                to: &mismatches
            )
        }
        let expectedCodes = oracleCase.expectedDiagnosticCodes.sorted()
        let actualCodes = observation.diagnosticCodes.sorted()
        if expectedCodes != actualCodes {
            mismatches.append(LogicDesignOracleMismatch(
                field: "diagnosticCodes",
                expected: expectedCodes.joined(separator: ","),
                actual: actualCodes.joined(separator: ",")
            ))
        }

        return LogicDesignOracleCorrelation(
            oracleID: manifest.oracleID,
            oracleVersion: manifest.oracleVersion,
            corpusID: manifest.corpusID,
            caseID: oracleCase.id,
            matched: mismatches.isEmpty,
            observation: observation,
            mismatches: mismatches
        )
    }

    private static func appendMismatch(
        field: String,
        expected: String?,
        actual: String?,
        to mismatches: inout [LogicDesignOracleMismatch]
    ) {
        guard expected != actual else { return }
        mismatches.append(LogicDesignOracleMismatch(
            field: field,
            expected: expected,
            actual: actual
        ))
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit }
    }
}
