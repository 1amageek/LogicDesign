import Foundation
import Testing
import LogicIR
import PowerIntent
import SystemVerilogFrontend
import XcircuitePackage

@Suite("LogicDesign retained fixture corpus")
struct FixtureCorpusTests {
    @Test("retained fixture expectations remain executable")
    func retainedManifestExpectationsExecute() async throws {
        let manifest = try readManifest()
        for entry in manifest.cases {
            let source = try readFixture("Fixtures/" + entry.path)
            let status: String
            if entry.kind == "systemVerilog" {
                let result = try await LogicElaboratingEngine(
                    clock: { Date(timeIntervalSince1970: 0) }
                ).execute(LogicElaborationRequest(
                    runID: "fixture-" + entry.id,
                    inputs: [],
                    topDesignName: entry.topDesignName,
                    sources: [SystemVerilogSourceUnit(
                        path: "Fixtures/" + entry.path,
                        source: source
                    )]
                ))
                status = result.status.rawValue
            } else {
                let format = PowerIntentFormat(rawValue: entry.kind) ?? .upf
                let result = try await PowerIntentParsingEngine(
                    clock: { Date(timeIntervalSince1970: 0) }
                ).execute(PowerIntentParsingRequest(
                    runID: "fixture-" + entry.id,
                    inputs: [],
                    design: LogicDesignReference(
                        artifact: XcircuiteFileReference(
                            path: "design.json",
                            kind: .rtl,
                            format: .json,
                            sha256: String(repeating: "1", count: 64),
                            byteCount: 0
                        ),
                        topDesignName: entry.topDesignName,
                        designDigest: String(repeating: "1", count: 64)
                    ),
                    format: format,
                    sources: [PowerIntentSourceUnit(
                        path: "Fixtures/" + entry.path,
                        source: source,
                        format: format
                    )]
                ))
                status = result.status.rawValue
            }
            #expect(status == entry.expectedStatus)
        }
    }

    @Test("retained fixture manifest matches file digests")
    func retainedManifestMatchesFiles() throws {
        let manifest = try readManifest()
        #expect(manifest.schemaVersion == 1)
        #expect(manifest.corpusID == "logic-design-native-smoke")
        #expect(manifest.cases.count == 8)
        #expect(Set(manifest.cases.map(\.id)).count == manifest.cases.count)
        #expect(Set(manifest.cases.map(\.path)).count == manifest.cases.count)

        let root = workspaceRoot()
        let hasher = XcircuiteHasher()
        for entry in manifest.cases {
            let url = root.appending(path: "Fixtures").appending(path: entry.path)
            let data = try Data(contentsOf: url)
            #expect(hasher.sha256(data: data) == entry.sha256)
        }
    }

    @Test("positive SystemVerilog fixture elaborates")
    func positiveSystemVerilogFixture() async throws {
        let source = try readFixture("Fixtures/positive/simple_counter.sv")
        let request = LogicElaborationRequest(
            runID: "fixture-positive",
            inputs: [],
            topDesignName: "counter",
            sources: [SystemVerilogSourceUnit(path: "Fixtures/positive/simple_counter.sv", source: source)]
        )
        let result = try await LogicElaboratingEngine(clock: { Date(timeIntervalSince1970: 0) }).execute(request)
        #expect(result.status == .completed)
        #expect(result.payload.snapshot?.rtl.modules.count == 1)
    }

    @Test("hierarchy fixture elaborates to a flat canonical snapshot")
    func hierarchyFixtureFlattens() async throws {
        let source = try readFixture("Fixtures/positive/hierarchy.sv")
        let result = try await LogicElaboratingEngine(
            clock: { Date(timeIntervalSince1970: 0) }
        ).execute(LogicElaborationRequest(
            runID: "fixture-hierarchy-flat",
            inputs: [],
            topDesignName: "top",
            sources: [SystemVerilogSourceUnit(
                path: "Fixtures/positive/hierarchy.sv",
                source: source
            )]
        ))

        #expect(result.status == .completed)
        #expect(result.payload.snapshot?.rtl.modules.count == 1)
        #expect(result.payload.snapshot?.rtl.modules.first?.instances.isEmpty == true)
        #expect(result.payload.snapshot?.rtl.modules.first?.assignments.count == 2)
    }

    @Test("constant conditional generate fixture elaborates")
    func conditionalGenerateFixture() async throws {
        let source = try readFixture("Fixtures/positive/conditional_generate.sv")
        let request = LogicElaborationRequest(
            runID: "fixture-conditional-generate",
            inputs: [],
            topDesignName: "conditional_generate",
            sources: [SystemVerilogSourceUnit(path: "Fixtures/positive/conditional_generate.sv", source: source)]
        )
        let result = try await LogicElaboratingEngine(clock: { Date(timeIntervalSince1970: 0) }).execute(request)
        #expect(result.status == .completed)
        #expect(result.payload.snapshot?.rtl.modules.first?.assignments.count == 1)
    }

    @Test("numeric preprocessor fixture elaborates")
    func preprocessorFixture() async throws {
        let source = try readFixture("Fixtures/positive/preprocessor.sv")
        let request = LogicElaborationRequest(
            runID: "fixture-preprocessor",
            inputs: [],
            topDesignName: "preprocessor",
            sources: [SystemVerilogSourceUnit(path: "Fixtures/positive/preprocessor.sv", source: source)]
        )
        let result = try await LogicElaboratingEngine(clock: { Date(timeIntervalSince1970: 0) }).execute(request)
        #expect(result.status == .completed)
        #expect(result.payload.snapshot?.rtl.modules.first?.ports.first?.range?.width == 4)
    }

    @Test("negative SystemVerilog fixture remains blocked")
    func negativeSystemVerilogFixture() throws {
        let source = try readFixture("Fixtures/negative/unsupported_generate.sv")
        let result = SystemVerilogParser().parse(
            [SystemVerilogSourceUnit(path: "Fixtures/negative/unsupported_generate.sv", source: source)],
            topDesignName: "generated"
        )
        #expect(result.unsupportedSemantics)
        #expect(result.diagnostics.contains { $0.code == "SV_UNSUPPORTED_GENERATE" })
    }

    @Test("CPF fixture parses with retained source provenance")
    func cpfFixture() throws {
        let source = try readFixture("Fixtures/power/sample.cpf")
        let result = PowerIntentParser().parse([
            PowerIntentSourceUnit(path: "Fixtures/power/sample.cpf", source: source, format: .cpf)
        ])
        #expect(result.design?.format == .cpf)
        #expect(result.design?.sourceFiles.first?.path == "Fixtures/power/sample.cpf")
        #expect(result.diagnostics.isEmpty)
    }

    private func readFixture(_ path: String) throws -> String {
        let root = workspaceRoot()
        return try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    private func readManifest() throws -> FixtureCorpusManifest {
        let data = try Data(contentsOf: workspaceRoot().appending(path: "Fixtures/manifest.json"))
        return try JSONDecoder().decode(FixtureCorpusManifest.self, from: data)
    }

    private func workspaceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
