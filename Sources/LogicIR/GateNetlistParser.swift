import Foundation

public struct GateNetlistParser: GateNetlistParsing {
    public init() {}

    public func parse(_ source: String, path: String, topDesignName: String) -> GateNetlistParseResult {
        var state = State(tokens: tokenize(source), path: path)
        var modules: [GateModule] = []
        while !state.isAtEnd {
            if state.match("module"), let module = state.parseModule() {
                modules.append(module)
            } else {
                state.diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "GATE_PARSE_EXPECTED_MODULE",
                    message: "Gate netlist input must contain module declarations.",
                    entity: state.current,
                    suggestedActions: ["provide_structural_verilog_netlist"]
                ))
                state.skipUntil(";")
            }
        }
        let design = modules.isEmpty ? nil : GateDesign(topModuleName: topDesignName, modules: modules)
        if let design {
            let validation = LogicDesignValidator().validate(design)
            state.diagnostics.append(contentsOf: validation.diagnostics)
        }
        return GateNetlistParseResult(design: design, diagnostics: state.diagnostics)
    }

    private func tokenize(_ source: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]
            if character.isWhitespace || "(),;".contains(character) {
                if !current.isEmpty { tokens.append(current); current = "" }
                if "(),;".contains(character) { tokens.append(String(character)) }
            } else if character == "." {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(".")
            } else {
                current.append(character)
            }
            index = source.index(after: index)
        }
        if !current.isEmpty { tokens.append(current) }
        tokens.append("")
        return tokens
    }

    private struct State {
        var tokens: [String]
        var index = 0
        var path: String
        var diagnostics: [LogicDiagnostic] = []

        var current: String { tokens[min(index, tokens.count - 1)] }
        var isAtEnd: Bool { current.isEmpty }

        mutating func advance() -> String {
            let value = current
            if !isAtEnd { index += 1 }
            return value
        }

        mutating func match(_ value: String) -> Bool {
            guard current == value else { return false }
            _ = advance()
            return true
        }

        mutating func expect(_ value: String) -> Bool {
            guard match(value) else {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "GATE_PARSE_EXPECTED_TOKEN",
                    message: "Expected '\(value)' in gate netlist.",
                    entity: current,
                    suggestedActions: ["correct_structural_netlist"]
                ))
                return false
            }
            return true
        }

        mutating func parseModule() -> GateModule? {
            guard !isAtEnd else { return nil }
            let name = advance()
            var ports: [RTLPort] = []
            if match("(") {
                var position = 0
                while !isAtEnd && current != ")" {
                    let portName = advance()
                    ports.append(RTLPort(
                        id: StableLogicID.make(kind: "gate-port", path: path, name: "\(name).\(portName)"),
                        name: portName,
                        direction: .internalSignal
                    ))
                    position += 1
                    if !match(",") { break }
                }
                _ = expect(")")
                _ = expect(";")
            } else {
                _ = expect(";")
            }

            var nets: [GateNet] = ports.map { port in
                GateNet(
                    id: StableLogicID.make(kind: "gate-net", path: path, name: "\(name).\(port.name)"),
                    name: port.name
                )
            }
            var cells: [GateCell] = []
            while !isAtEnd && current != "endmodule" {
                if match("wire") {
                    while !isAtEnd && current != ";" {
                        let wire = advance()
                        if !wire.isEmpty && wire != "," {
                            nets.append(GateNet(
                                id: StableLogicID.make(kind: "gate-net", path: path, name: "\(name).\(wire)"),
                                name: wire
                            ))
                        }
                    }
                    _ = match(";")
                    continue
                }
                guard let cell = parseCell(moduleName: name) else {
                    skipUntil(";")
                    continue
                }
                cells.append(cell)
            }
            _ = expect("endmodule")

            var netIndex = Dictionary(uniqueKeysWithValues: nets.enumerated().map { ($0.element.name, $0.offset) })
            for cell in cells {
                for pin in cell.pins {
                    guard let netID = pin.netID else { continue }
                    if let index = netIndex[netID] {
                        if pin.direction == .output {
                            nets[index].driverPinIDs.append(pin.id)
                        } else {
                            nets[index].loadPinIDs.append(pin.id)
                        }
                    } else {
                        let newNet = GateNet(
                            id: StableLogicID.make(kind: "gate-net", path: path, name: "\(name).\(netID)"),
                            name: netID,
                            driverPinIDs: pin.direction == .output ? [pin.id] : [],
                            loadPinIDs: pin.direction == .output ? [] : [pin.id]
                        )
                        netIndex[netID] = nets.count
                        nets.append(newNet)
                    }
                }
            }
            let resolvedCells = cells.map { cell in
                var cell = cell
                cell.pins = cell.pins.map { pin in
                    var pin = pin
                    if let netName = pin.netID, let netIndex = netIndex[netName] {
                        pin.netID = nets[netIndex].id
                    }
                    return pin
                }
                return cell
            }
            return GateModule(
                id: StableLogicID.make(kind: "gate-module", path: path, name: name),
                name: name,
                ports: ports,
                cells: resolvedCells,
                nets: nets
            )
        }

        mutating func parseCell(moduleName: String) -> GateCell? {
            guard current != "endmodule" && current != ";" else { return nil }
            let type = advance()
            guard !isAtEnd else { return nil }
            let instanceName = advance()
            guard match("(") else {
                index -= 1
                return nil
            }
            var pins: [GatePin] = []
            while !isAtEnd && current != ")" {
                var pinName = "pin\(pins.count)"
                if match(".") {
                    pinName = advance()
                }
                guard match("(") else { break }
                let netName = advance()
                _ = expect(")")
                let direction: GatePinDirection = ["Y", "Z", "Q", "QN", "O", "OUT"].contains(pinName.uppercased()) ? .output : .input
                pins.append(GatePin(
                    id: StableLogicID.make(kind: "gate-pin", path: path, name: "\(moduleName).\(instanceName).\(pinName)"),
                    name: pinName,
                    direction: direction,
                    netID: netName
                ))
                if !match(",") { break }
            }
            _ = expect(")")
            _ = expect(";")
            return GateCell(
                id: StableLogicID.make(kind: "gate-cell", path: path, name: "\(moduleName).\(instanceName)"),
                type: type,
                instanceName: instanceName,
                pins: pins
            )
        }

        mutating func skipUntil(_ value: String) {
            while !isAtEnd && current != value { _ = advance() }
            _ = match(value)
        }
    }
}
