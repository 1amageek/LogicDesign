import Foundation
import LogicDesign
import LogicIR
import PowerIntent
import SystemVerilogFrontend
import XcircuitePackage

public enum LogicDesignCLI {
    public static func run(arguments: [String]) async -> Int {
        do {
            let command = try Command(arguments: arguments)
            switch command.kind {
            case .help:
                try emit(Help.text)
                return 0
            case .capabilities:
                try emit(LogicDesignCapabilityReport.current)
                return 0
            case .parse, .validate:
                let result = try await runSystemVerilog(command)
                try emit(result)
                return result.status == .completed ? 0 : 2
            case .correlate:
                let result = try await runOracleCorrelation(command)
                try emit(result)
                return result.matched ? 0 : 2
            case .gateParse:
                let result = try runGateParse(command)
                try emit(result)
                return result.isValid ? 0 : 2
            case .powerIntent:
                let result = try await runPowerIntent(command)
                try emit(result)
                return result.status == .completed ? 0 : 2
            }
        } catch {
            let output = CLIErrorOutput(error: error.localizedDescription)
            do {
                try emit(output)
            } catch {
                FileHandle.standardError.write(Data("\(output.error)\n".utf8))
            }
            return 64
        }
    }

    private static func runSystemVerilog(_ command: Command) async throws -> XcircuiteEngineResultEnvelope<LogicElaborationPayload> {
        let source = try readSource(at: command.input)
        let sourceUnit = SystemVerilogSourceUnit(path: command.input, source: source)
        let request = LogicElaborationRequest(
            runID: command.runID,
            inputs: [],
            topDesignName: command.topDesign,
            sources: [sourceUnit]
        )
        let engine = LogicElaboratingEngine(clock: { Date(timeIntervalSince1970: 0) })
        let result = try await engine.execute(request)
        if let output = command.output, let snapshot = result.payload.snapshot {
            let data = try LogicDesignSnapshotCodec.encode(snapshot)
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        }
        return result
    }

    private static func runOracleCorrelation(_ command: Command) async throws -> LogicDesignOracleCorrelation {
        let sourceData = try readSourceData(at: command.input)
        guard let source = String(data: sourceData, encoding: .utf8) else {
            throw CLIError.readFailed(path: command.input, message: "The input is not valid UTF-8.")
        }
        let oracleData = try readSourceData(at: command.oraclePath)
        let manifest: LogicDesignOracleManifest
        do {
            manifest = try JSONDecoder().decode(LogicDesignOracleManifest.self, from: oracleData)
        } catch {
            throw CLIError.readFailed(path: command.oraclePath, message: error.localizedDescription)
        }
        try LogicDesignOracleCorrelator.validate(manifest)
        guard let oracleCase = manifest.caseWithID(command.caseID) else {
            throw LogicDesignOracleCorrelationError.caseNotFound(command.caseID)
        }
        let topDesignName = command.topDesign == "top"
            ? oracleCase.topDesignName
            : command.topDesign
        let result = try await LogicElaboratingEngine(
            clock: { Date(timeIntervalSince1970: 0) }
        ).execute(LogicElaborationRequest(
            runID: command.runID,
            inputs: [],
            topDesignName: topDesignName,
            sources: [SystemVerilogSourceUnit(path: command.input, source: source)]
        ))
        let sourceSHA256 = XcircuiteHasher().sha256(data: sourceData)
        return try LogicDesignOracleCorrelator.correlate(
            manifest: manifest,
            oracleCase: oracleCase,
            sourceSHA256: sourceSHA256,
            topDesignName: topDesignName,
            result: result
        )
    }

    private static func runPowerIntent(_ command: Command) async throws -> XcircuiteEngineResultEnvelope<PowerIntentParsingPayload> {
        let source = try readSource(at: command.input)
        let sourceUnit = PowerIntentSourceUnit(path: command.input, source: source, format: command.format)
        let designReference = LogicDesignReference(
            artifact: XcircuiteFileReference(
                path: "design.json",
                kind: .rtl,
                format: .json,
                sha256: command.designDigest,
                byteCount: 0
            ),
            topDesignName: command.topDesign,
            designDigest: command.designDigest
        )
        let request = PowerIntentParsingRequest(
            runID: command.runID,
            inputs: [],
            design: designReference,
            format: command.format,
            sources: [sourceUnit]
        )
        let engine = PowerIntentParsingEngine(clock: { Date(timeIntervalSince1970: 0) })
        let result = try await engine.execute(request)
        if let output = command.output, let intent = result.payload.intent {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(intent).write(to: URL(fileURLWithPath: output), options: .atomic)
        }
        return result
    }

    private static func runGateParse(_ command: Command) throws -> GateNetlistParseResult {
        let source = try readSource(at: command.input)
        return GateNetlistParser().parse(source, path: command.input, topDesignName: command.topDesign)
    }

    private static func readSource(at path: String) throws -> String {
        do {
            return try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        } catch {
            throw CLIError.readFailed(path: path, message: error.localizedDescription)
        }
    }

    private static func readSourceData(at path: String) throws -> Data {
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw CLIError.readFailed(path: path, message: error.localizedDescription)
        }
    }

    private static func emit<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }

    private struct Command: Sendable {
        enum Kind: Sendable { case help, capabilities, parse, validate, correlate, gateParse, powerIntent }
        var kind: Kind
        var input: String = ""
        var oraclePath: String = ""
        var caseID: String = ""
        var output: String?
        var topDesign: String = "top"
        var runID: String = "logic-design-cli"
        var format: PowerIntentFormat = .upf
        var designDigest: String = ""

        init(arguments: [String]) throws {
            guard let first = arguments.first else { kind = .help; return }
            switch first {
            case "help", "--help", "-h": kind = .help; return
            case "capabilities": kind = .capabilities; return
            case "parse": kind = .parse
            case "validate": kind = .validate
            case "correlate": kind = .correlate
            case "gate-parse": kind = .gateParse
            case "power-intent": kind = .powerIntent
            default: throw CLIError.unknownCommand(first)
            }
            var index = 1
            while index < arguments.count {
                let argument = arguments[index]
                guard index + 1 < arguments.count else { throw CLIError.missingValue(argument) }
                switch argument {
                case "--input": input = arguments[index + 1]
                case "--oracle": oraclePath = arguments[index + 1]
                case "--case": caseID = arguments[index + 1]
                case "--output": output = arguments[index + 1]
                case "--top": topDesign = arguments[index + 1]
                case "--run-id": runID = arguments[index + 1]
                case "--design-digest": designDigest = arguments[index + 1]
                case "--format":
                    guard let parsed = PowerIntentFormat(rawValue: arguments[index + 1]) else { throw CLIError.invalidValue(argument) }
                    format = parsed
                default: throw CLIError.unknownArgument(argument)
                }
                index += 2
            }
            if kind == .parse || kind == .validate || kind == .correlate || kind == .gateParse || kind == .powerIntent, input.isEmpty {
                throw CLIError.missingValue("--input")
            }
            if kind == .correlate, oraclePath.isEmpty {
                throw CLIError.missingValue("--oracle")
            }
            if kind == .correlate, caseID.isEmpty {
                throw CLIError.missingValue("--case")
            }
            if kind == .powerIntent, designDigest.isEmpty {
                throw CLIError.missingValue("--design-digest")
            }
        }
    }

    private enum CLIError: Error, LocalizedError {
        case unknownCommand(String)
        case unknownArgument(String)
        case missingValue(String)
        case invalidValue(String)
        case readFailed(path: String, message: String)

        var errorDescription: String? {
            switch self {
            case .unknownCommand(let value): return "Unknown command: \(value)"
            case .unknownArgument(let value): return "Unknown argument: \(value)"
            case .missingValue(let value): return "Missing value for \(value)"
            case .invalidValue(let value): return "Invalid value for \(value)"
            case .readFailed(let path, let message): return "Could not read \(path): \(message)"
            }
        }
    }

    private struct CLIErrorOutput: Codable {
        var error: String
    }

    private enum Help {
        static let text = [
            "commands:",
            "  capabilities",
            "  parse --input <file> --top <module> [--output <snapshot.json>]",
            "  validate --input <file> --top <module>",
            "  correlate --input <file> --oracle <manifest.json> --case <case-id> [--top <module>]",
            "  gate-parse --input <file> --top <module>",
            "  power-intent --input <file> --format <upf|cpf> --design-digest <sha256> [--output <intent.json>]"
        ].joined(separator: "\n")
    }
}
