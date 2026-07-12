import Foundation
import XcircuitePackage

public struct LogicDesignValidator: LogicDesignValidating {
    public init() {}

    public func validate(_ design: RTLDesign) -> LogicValidationResult {
        var diagnostics: [LogicDiagnostic] = []
        let moduleNames = design.modules.map(\.name)

        if design.topModuleName.isEmpty {
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "LOGIC_TOP_MISSING",
                message: "A top module name is required.",
                suggestedActions: ["select_top_module"]
            ))
        } else if !moduleNames.contains(design.topModuleName) {
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "LOGIC_TOP_UNRESOLVED",
                message: "The selected top module is not defined.",
                entity: design.topModuleName,
                suggestedActions: ["add_module_definition", "select_existing_top"]
            ))
        }

        if Set(moduleNames).count != moduleNames.count {
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "LOGIC_DUPLICATE_MODULE",
                message: "Module names must be unique.",
                suggestedActions: ["rename_duplicate_module"]
            ))
        }

        for module in design.modules {
            var names = Set<String>()
            for port in module.ports {
                appendDuplicateDiagnostic(
                    name: port.name,
                    kind: "port",
                    module: module,
                    names: &names,
                    diagnostics: &diagnostics,
                    source: port.source
                )
            }
            for signal in module.signals {
                appendDuplicateDiagnostic(
                    name: signal.name,
                    kind: "signal",
                    module: module,
                    names: &names,
                    diagnostics: &diagnostics,
                    source: signal.source
                )
            }
            for memory in module.memories {
                appendDuplicateDiagnostic(
                    name: memory.name,
                    kind: "memory",
                    module: module,
                    names: &names,
                    diagnostics: &diagnostics,
                    source: memory.source
                )
            }

            for instance in module.instances {
                guard moduleNames.contains(instance.moduleName) else {
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "LOGIC_INSTANCE_UNRESOLVED",
                        message: "Instance references an undefined module.",
                        entity: "\(module.name).\(instance.instanceName)",
                        location: instance.source,
                        suggestedActions: ["add_referenced_module", "correct_instance_type"]
                    ))
                    continue
                }
            }

            let knownNames = names
            for assignment in module.assignments {
                validateExpression(
                    assignment.target,
                    knownNames: knownNames,
                    module: module,
                    diagnostics: &diagnostics,
                    source: assignment.source
                )
                validateExpression(
                    assignment.value,
                    knownNames: knownNames,
                    module: module,
                    diagnostics: &diagnostics,
                    source: assignment.source
                )
            }
            for process in module.processes {
                for statement in process.statements {
                    validateStatement(
                        statement,
                        knownNames: knownNames,
                        module: module,
                        diagnostics: &diagnostics,
                        source: process.source
                    )
                }
            }
        }

        return LogicValidationResult(
            isValid: !diagnostics.contains { $0.severity == .error },
            diagnostics: diagnostics
        )
    }

    public func validate(_ design: GateDesign) -> LogicValidationResult {
        var diagnostics: [LogicDiagnostic] = []
        let moduleNames = design.modules.map(\.name)
        guard !design.topModuleName.isEmpty else {
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "GATE_TOP_MISSING",
                message: "A gate design requires a top module name.",
                suggestedActions: ["select_top_module"]
            ))
            return LogicValidationResult(isValid: false, diagnostics: diagnostics)
        }
        guard moduleNames.contains(design.topModuleName) else {
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "GATE_TOP_UNRESOLVED",
                message: "The selected gate top module is not defined.",
                entity: design.topModuleName,
                suggestedActions: ["add_module_definition", "select_existing_top"]
            ))
            return LogicValidationResult(isValid: false, diagnostics: diagnostics)
        }

        if Set(moduleNames).count != moduleNames.count {
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "GATE_DUPLICATE_MODULE",
                message: "Gate module names must be unique.",
                suggestedActions: ["rename_duplicate_module"]
            ))
        }
        let moduleIDs = design.modules.map(\.id)
        if moduleIDs.contains(where: { $0.isEmpty }) || Set(moduleIDs).count != moduleIDs.count {
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "GATE_DUPLICATE_MODULE_ID",
                message: "Gate modules must have non-empty stable unique identities.",
                suggestedActions: ["regenerate_stable_ids"]
            ))
        }

        for module in design.modules {
            let netIDs = Set(module.nets.map(\.id))
            let cellIDs = Set(module.cells.map(\.id))
            let netNames = module.nets.map(\.name)
            let instanceNames = module.cells.map(\.instanceName)
            if Set(netNames).count != netNames.count {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "GATE_DUPLICATE_NET_NAME",
                    message: "Gate net names must be unique within a module.",
                    entity: module.name,
                    suggestedActions: ["rename_duplicate_net"]
                ))
            }
            if Set(instanceNames).count != instanceNames.count {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "GATE_DUPLICATE_INSTANCE_NAME",
                    message: "Gate instance names must be unique within a module.",
                    entity: module.name,
                    suggestedActions: ["rename_duplicate_instance"]
                ))
            }
            if module.nets.contains(where: { $0.id.isEmpty || $0.name.isEmpty }) {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "GATE_NET_ID_MISSING",
                    message: "Gate nets require non-empty stable IDs and names.",
                    entity: module.name,
                    suggestedActions: ["regenerate_stable_ids", "name_all_nets"]
                ))
            }

            var pinsByID: [String: GatePin] = [:]
            for cell in module.cells {
                if cell.id.isEmpty || cell.type.isEmpty || cell.instanceName.isEmpty {
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "GATE_CELL_ID_MISSING",
                        message: "Gate cells require non-empty IDs, types and instance names.",
                        entity: module.name,
                        suggestedActions: ["regenerate_stable_ids", "provide_cell_type"]
                    ))
                }
                var pinNames = Set<String>()
                for pin in cell.pins {
                    if let netID = pin.netID, !netIDs.contains(netID) {
                        diagnostics.append(LogicDiagnostic(
                            severity: .error,
                            code: "GATE_NET_UNRESOLVED",
                            message: "Gate pin references an undefined net.",
                            entity: "\(module.name).\(cell.instanceName).\(pin.name)",
                            location: pin.source,
                            suggestedActions: ["define_net", "correct_pin_connection"]
                        ))
                    }
                    if !pinNames.insert(pin.name).inserted {
                        diagnostics.append(LogicDiagnostic(
                            severity: .error,
                            code: "GATE_DUPLICATE_PIN_NAME",
                            message: "Pin names must be unique within a cell.",
                            entity: "\(module.name).\(cell.instanceName).\(pin.name)",
                            location: pin.source,
                            suggestedActions: ["rename_duplicate_pin"]
                        ))
                    }
                    guard !pin.id.isEmpty else {
                        diagnostics.append(LogicDiagnostic(
                            severity: .error,
                            code: "GATE_PIN_ID_MISSING",
                            message: "Gate pins require non-empty stable IDs.",
                            entity: "\(module.name).\(cell.instanceName).\(pin.name)",
                            location: pin.source,
                            suggestedActions: ["regenerate_stable_ids"]
                        ))
                        continue
                    }
                    guard pinsByID[pin.id] == nil else {
                        diagnostics.append(LogicDiagnostic(
                            severity: .error,
                            code: "GATE_DUPLICATE_PIN_ID",
                            message: "Gate pin IDs must be unique within a module.",
                            entity: "\(module.name).\(cell.instanceName).\(pin.name)",
                            location: pin.source,
                            suggestedActions: ["regenerate_stable_ids"]
                        ))
                        continue
                    }
                    pinsByID[pin.id] = pin
                }
            }

            let pinIDs = module.cells.flatMap { $0.pins.map(\.id) }
            if Set(pinIDs).count != pinIDs.count || cellIDs.count != module.cells.count {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "GATE_DUPLICATE_ID",
                    message: "Gate cells and pins must have stable unique identities.",
                    entity: module.name,
                    suggestedActions: ["regenerate_stable_ids"]
                ))
            }

            for net in module.nets {
                let driverIDs = net.driverPinIDs
                let loadIDs = net.loadPinIDs
                if Set(driverIDs).count != driverIDs.count || Set(loadIDs).count != loadIDs.count {
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "GATE_DUPLICATE_NET_PIN_REFERENCE",
                        message: "A gate net cannot list the same pin more than once.",
                        entity: "\(module.name).\(net.name)",
                        location: net.source,
                        suggestedActions: ["deduplicate_net_connections"]
                    ))
                }
                if !Set(driverIDs).intersection(loadIDs).isEmpty {
                    diagnostics.append(LogicDiagnostic(
                        severity: .error,
                        code: "GATE_DRIVER_LOAD_OVERLAP",
                        message: "A pin cannot be both a driver and a load of the same net.",
                        entity: "\(module.name).\(net.name)",
                        location: net.source,
                        suggestedActions: ["correct_pin_direction"]
                    ))
                }
                for pinID in driverIDs {
                    validateNetPinReference(
                        pinID,
                        net: net,
                        expectedDirection: .output,
                        moduleName: module.name,
                        pinsByID: pinsByID,
                        diagnostics: &diagnostics
                    )
                }
                for pinID in loadIDs {
                    validateNetPinReference(
                        pinID,
                        net: net,
                        expectedDirection: .input,
                        moduleName: module.name,
                        pinsByID: pinsByID,
                        diagnostics: &diagnostics
                    )
                }
            }
        }
        return LogicValidationResult(
            isValid: !diagnostics.contains { $0.severity == .error },
            diagnostics: diagnostics
        )
    }

    private func validateNetPinReference(
        _ pinID: String,
        net: GateNet,
        expectedDirection: GatePinDirection,
        moduleName: String,
        pinsByID: [String: GatePin],
        diagnostics: inout [LogicDiagnostic]
    ) {
        guard let pin = pinsByID[pinID] else {
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "GATE_NET_PIN_UNRESOLVED",
                message: "Gate net references an undefined pin.",
                entity: "\(moduleName).\(net.name).\(pinID)",
                location: net.source,
                suggestedActions: ["define_pin", "correct_net_pin_reference"]
            ))
            return
        }
        guard pin.netID == net.id else {
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "GATE_NET_PIN_MISMATCH",
                message: "Gate net pin reference does not point back to the same net.",
                entity: "\(moduleName).\(net.name).\(pin.name)",
                location: pin.source,
                suggestedActions: ["rebuild_net_connectivity"]
            ))
            return
        }
        if pin.direction != expectedDirection {
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "GATE_NET_DIRECTION_MISMATCH",
                message: "Gate net driver/load classification disagrees with pin direction.",
                entity: "\(moduleName).\(net.name).\(pin.name)",
                location: pin.source,
                suggestedActions: ["correct_pin_direction", "rebuild_net_connectivity"]
            ))
        }
    }

    private func appendDuplicateDiagnostic(
        name: String,
        kind: String,
        module: RTLModule,
        names: inout Set<String>,
        diagnostics: inout [LogicDiagnostic],
        source: LogicSourceSpan?
    ) {
        guard !names.insert(name).inserted else { return }
        diagnostics.append(LogicDiagnostic(
            severity: .error,
            code: "LOGIC_DUPLICATE_SYMBOL",
            message: "The module contains duplicate declarations.",
            entity: "\(module.name).\(name)",
            location: source,
            suggestedActions: ["rename_duplicate_\(kind)"]
        ))
    }

    private func validateStatement(
        _ statement: RTLStatement,
        knownNames: Set<String>,
        module: RTLModule,
        diagnostics: inout [LogicDiagnostic],
        source: LogicSourceSpan?
    ) {
        switch statement {
        case .assignment(let assignment):
            validateExpression(assignment.target, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: assignment.source ?? source)
            validateExpression(assignment.value, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: assignment.source ?? source)
        case .block(let statements):
            for child in statements {
                validateStatement(child, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
            }
        case .conditional(let condition, let ifTrue, let ifFalse):
            validateExpression(condition, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
            for child in ifTrue + ifFalse {
                validateStatement(child, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
            }
        case .caseStatement(let expression, let items, let defaultStatements):
            validateExpression(expression, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
            for item in items {
                for match in item.matches {
                    validateExpression(match, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: item.source ?? source)
                }
                for child in item.statements {
                    validateStatement(child, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: item.source ?? source)
                }
            }
            for child in defaultStatements {
                validateStatement(child, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
            }
        case .typedCaseStatement(_, let expression, let items, let defaultStatements):
            validateExpression(expression, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
            for item in items {
                for match in item.matches {
                    validateExpression(match, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: item.source ?? source)
                }
                for child in item.statements {
                    validateStatement(child, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: item.source ?? source)
                }
            }
            for child in defaultStatements {
                validateStatement(child, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
            }
        case .null:
            break
        }
    }

    private func validateExpression(
        _ expression: RTLExpression,
        knownNames: Set<String>,
        module: RTLModule,
        diagnostics: inout [LogicDiagnostic],
        source: LogicSourceSpan?
    ) {
        switch expression {
        case .identifier(let name):
            guard knownNames.contains(name) else {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "LOGIC_REFERENCE_UNRESOLVED",
                    message: "Expression references an undefined signal, port or memory.",
                    entity: "\(module.name).\(name)",
                    location: source,
                    suggestedActions: ["declare_signal", "correct_reference"]
                ))
                return
            }
        case .integer, .string:
            break
        case .unary(_, let operand):
            validateExpression(operand, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
        case .binary(_, let left, let right):
            validateExpression(left, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
            validateExpression(right, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
        case .ternary(let condition, let ifTrue, let ifFalse):
            validateExpression(condition, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
            validateExpression(ifTrue, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
            validateExpression(ifFalse, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
        case .concatenate(let values):
            for value in values {
                validateExpression(value, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
            }
        case .index(let value, let index):
            validateExpression(value, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
            validateExpression(index, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
        case .partSelect(let value, let msb, let lsb):
            validateExpression(value, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
            validateExpression(msb, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
            validateExpression(lsb, knownNames: knownNames, module: module, diagnostics: &diagnostics, source: source)
        }
    }
}
