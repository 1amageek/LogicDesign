import Foundation
import LogicIR

public struct PowerIntentParser: Sendable {
    public init() {}

    public func parse(_ sources: [PowerIntentSourceUnit]) -> PowerIntentParseResult {
        guard let first = sources.first else {
            return PowerIntentParseResult(
                design: nil,
                diagnostics: [LogicDiagnostic(
                    severity: .error,
                    code: "POWER_INPUT_EMPTY",
                    message: "At least one UPF or CPF source is required.",
                    suggestedActions: ["provide_power_intent_source"]
                )]
            )
        }

        var domains: [PowerDomain] = []
        var supplySets: [PowerSupplySet] = []
        var isolations: [PowerIntentIsolation] = []
        var levelShifters: [PowerIntentLevelShifter] = []
        var retentions: [PowerIntentRetention] = []
        var directives: [String] = []
        var diagnostics: [LogicDiagnostic] = []
        var unsupported = false

        for source in sources {
            let lines = source.source.split(separator: "\n", omittingEmptySubsequences: false)
            var offset = 0
            for line in lines {
                let text = String(line)
                let tokens = tokenize(text)
                let span = LogicSourceSpan(
                    start: LogicSourceLocation(path: source.path, line: lineNumber(offset: offset, source: source.source), column: 1, offset: offset),
                    end: LogicSourceLocation(path: source.path, line: lineNumber(offset: offset, source: source.source), column: max(1, text.count + 1), offset: offset + text.count)
                )
                offset += text.count + 1
                guard let command = tokens.first else { continue }
                let options = parseOptions(Array(tokens.dropFirst()))
                switch command {
                case "create_supply_set":
                    let name = firstValue(after: command, tokens: tokens) ?? options["-supply_set"]
                    guard let name, !name.hasPrefix("-") else {
                        diagnostics.append(error("POWER_SUPPLY_SET_NAME_MISSING", "create_supply_set requires a supply set name.", span: span))
                        continue
                    }
                    supplySets.append(PowerSupplySet(
                        id: StableLogicID.make(kind: "supply-set", path: source.path, name: name),
                        name: name,
                        supplyNets: values(options["-supply_net"] ?? options["-supply_nets"] ?? ""),
                        source: span
                    ))
                case "create_power_domain":
                    let name = options["-domain"] ?? firstPositional(tokens)
                    guard let name else {
                        diagnostics.append(error("POWER_DOMAIN_NAME_MISSING", "create_power_domain requires a domain name.", span: span))
                        continue
                    }
                    domains.append(PowerDomain(
                        id: StableLogicID.make(kind: "power-domain", path: source.path, name: name),
                        name: name,
                        elements: values(options["-elements"] ?? ""),
                        primarySupplySet: options["-supply"] ?? options["-supply_set"],
                        source: span
                    ))
                case "set_domain_supply_net", "connect_supply_net":
                    let domain = options["-domain"] ?? firstPositional(tokens)
                    let supply = options["-supply_net"] ?? options["-primary_power_net"] ?? positional(tokens, index: 1)
                    if let domain, let supply {
                        if let index = domains.firstIndex(where: { $0.name == domain }) {
                            domains[index].primarySupplyNet = supply
                        } else {
                            diagnostics.append(error("POWER_DOMAIN_UNRESOLVED", "The supply command references an undefined domain.", entity: domain, span: span))
                        }
                    } else {
                        diagnostics.append(error("POWER_SUPPLY_CONNECTION_INCOMPLETE", "A domain and supply net are required.", span: span))
                    }
                case "set_isolation", "create_isolation_rule":
                    let name = options["-name"] ?? options["-isolation"] ?? firstPositional(tokens) ?? "isolation_\(isolations.count)"
                    let domain = options["-domain"] ?? options["-from"] ?? positional(tokens, index: 1)
                    guard let domain else {
                        diagnostics.append(error("POWER_ISOLATION_DOMAIN_MISSING", "An isolation rule requires a source domain.", span: span))
                        continue
                    }
                    isolations.append(PowerIntentIsolation(
                        id: StableLogicID.make(kind: "isolation", path: source.path, name: name),
                        name: name,
                        domain: domain,
                        appliesTo: options["-applies_to"] ?? options["-applies-to"] ?? "all",
                        clampValue: options["-clamp_value"] ?? options["-clamp-value"] ?? "0",
                        isolationSignal: options["-isolation_signal"] ?? options["-isolation_signal_name"],
                        source: span
                    ))
                case "set_level_shifter", "create_level_shifter_rule":
                    let name = options["-name"] ?? options["-rule"] ?? firstPositional(tokens) ?? "level_shifter_\(levelShifters.count)"
                    levelShifters.append(PowerIntentLevelShifter(
                        id: StableLogicID.make(kind: "level-shifter", path: source.path, name: name),
                        name: name,
                        fromDomain: options["-from"] ?? options["-source"] ?? positional(tokens, index: 1),
                        toDomain: options["-to"] ?? options["-sink"] ?? positional(tokens, index: 2),
                        appliesTo: options["-applies_to"] ?? "all",
                        source: span
                    ))
                case "set_retention", "create_retention_rule":
                    let name = options["-name"] ?? options["-retention"] ?? firstPositional(tokens) ?? "retention_\(retentions.count)"
                    let domain = options["-domain"] ?? positional(tokens, index: 1)
                    guard let domain else {
                        diagnostics.append(error("POWER_RETENTION_DOMAIN_MISSING", "A retention rule requires a domain.", span: span))
                        continue
                    }
                    retentions.append(PowerIntentRetention(
                        id: StableLogicID.make(kind: "retention", path: source.path, name: name),
                        name: name,
                        domain: domain,
                        retentionRegister: options["-retention_register"],
                        saveSignal: options["-save_signal"],
                        restoreSignal: options["-restore_signal"],
                        source: span
                    ))
                case "create_nominal_condition", "create_power_mode", "set_scope", "set_port_attributes", "set_related_supply_net":
                    directives.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
                default:
                    unsupported = true
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "POWER_UNSUPPORTED_COMMAND",
                        message: "The power-intent command is not supported by the native parser.",
                        entity: command,
                        location: span,
                        suggestedActions: ["lower_to_supported_power_intent", "use_external_power_intent_frontend"]
                    ))
                }
            }
        }

        let design = PowerIntentDesign(
            format: first.format,
            domains: unique(domains, key: { $0.name }),
            supplySets: unique(supplySets, key: { $0.name }),
            isolationPolicies: unique(isolations, key: { $0.name }),
            levelShifters: unique(levelShifters, key: { $0.name }),
            retentionPolicies: unique(retentions, key: { $0.name }),
            directives: directives,
            sourceFiles: sources.map(\.file)
        )
        return PowerIntentParseResult(design: design, diagnostics: diagnostics, unsupportedSemantics: unsupported)
    }

    private func tokenize(_ line: String) -> [String] {
        let withoutComment = line.components(separatedBy: "#").first ?? line
        var values: [String] = []
        var current = ""
        var inBrace = false
        var inQuote = false
        for character in withoutComment {
            if character == "\"" {
                inQuote.toggle()
                continue
            }
            if character == "{" && !inQuote {
                if !current.isEmpty { values.append(current); current = "" }
                inBrace = true
                continue
            }
            if character == "}" && !inQuote {
                if !current.isEmpty { values.append(current); current = "" }
                inBrace = false
                continue
            }
            if character.isWhitespace || character == ";" {
                if !current.isEmpty { values.append(current); current = "" }
            } else if character == "," && !inBrace {
                if !current.isEmpty { values.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { values.append(current) }
        return values
    }

    private func parseOptions(_ tokens: [String]) -> [String: String] {
        var options: [String: String] = [:]
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.hasPrefix("-") {
                if index + 1 < tokens.count, !tokens[index + 1].hasPrefix("-") {
                    options[token] = tokens[index + 1]
                    index += 2
                } else {
                    options[token] = "true"
                    index += 1
                }
            } else {
                index += 1
            }
        }
        return options
    }

    private func firstValue(after command: String, tokens: [String]) -> String? {
        tokens.dropFirst().first { !$0.hasPrefix("-") }
    }

    private func firstPositional(_ tokens: [String]) -> String? {
        tokens.dropFirst().first { !$0.hasPrefix("-") }
    }

    private func positional(_ tokens: [String], index: Int) -> String? {
        tokens.dropFirst().filter { !$0.hasPrefix("-") }.dropFirst(index - 1).first
    }

    private func values(_ value: String) -> [String] {
        value.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
    }

    private func lineNumber(offset: Int, source: String) -> Int {
        source.prefix(offset).reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
    }

    private func error(_ code: String, _ message: String, entity: String? = nil, span: LogicSourceSpan) -> LogicDiagnostic {
        LogicDiagnostic(severity: .error, code: code, message: message, entity: entity, location: span, suggestedActions: ["correct_power_intent"])
    }

    private func unique<T>(_ values: [T], key: (T) -> String) -> [T] {
        var result: [T] = []
        var seen = Set<String>()
        for value in values where seen.insert(key(value)).inserted { result.append(value) }
        return result
    }
}
