import Foundation

public struct RTLHierarchyElaborator: RTLHierarchyElaborating {
    public init() {}

    public func elaborate(_ design: RTLDesign) -> RTLHierarchyElaborationResult {
        var diagnostics: [LogicDiagnostic] = []
        guard !design.topModuleName.isEmpty else {
            return RTLHierarchyElaborationResult(
                design: nil,
                diagnostics: [diagnostic(
                    code: "LOGIC_HIERARCHY_TOP_MISSING",
                    message: "A top module is required before hierarchy elaboration.",
                    actions: ["select_top_module"]
                )]
            )
        }

        let modulesByName = Dictionary(grouping: design.modules, by: \.name)
        if let duplicateName = modulesByName.first(where: { $0.value.count > 1 })?.key {
            diagnostics.append(diagnostic(
                code: "LOGIC_HIERARCHY_DUPLICATE_MODULE",
                message: "Hierarchy elaboration requires unique module names.",
                entity: duplicateName,
                actions: ["rename_duplicate_module"]
            ))
        }
        guard let topModule = modulesByName[design.topModuleName]?.first else {
            diagnostics.append(diagnostic(
                code: "LOGIC_HIERARCHY_TOP_UNRESOLVED",
                message: "The selected top module is not present in the design.",
                entity: design.topModuleName,
                actions: ["add_top_module", "select_existing_top"]
            ))
            return RTLHierarchyElaborationResult(design: nil, diagnostics: diagnostics)
        }
        guard diagnostics.isEmpty else {
            return RTLHierarchyElaborationResult(design: nil, diagnostics: diagnostics)
        }

        var flattenedTop = topModule
        flattenedTop.instances = []
        flattenedTop.generateBlocks = []
        var state = State(
            modulesByName: modulesByName,
            topModuleName: design.topModuleName,
            diagnostics: []
        )
        state.flattenInstances(
            in: topModule,
            prefix: "",
            mapping: [:],
            path: [topModule.name],
            into: &flattenedTop
        )
        diagnostics.append(contentsOf: state.diagnostics)
        guard !diagnostics.contains(where: { $0.severity == .error }) else {
            return RTLHierarchyElaborationResult(design: nil, diagnostics: diagnostics)
        }

        return RTLHierarchyElaborationResult(
            design: RTLDesign(
                topModuleName: design.topModuleName,
                modules: [flattenedTop],
                sourceFiles: design.sourceFiles,
                schemaVersion: design.schemaVersion
            ),
            diagnostics: diagnostics
        )
    }

    private struct State {
        let modulesByName: [String: [RTLModule]]
        let topModuleName: String
        var diagnostics: [LogicDiagnostic]

        mutating func flattenInstances(
            in module: RTLModule,
            prefix: String,
            mapping: [String: RTLExpression],
            path: [String],
            into flattenedTop: inout RTLModule
        ) {
            guard module.memories.isEmpty else {
                diagnostics.append(diagnostic(
                    code: "LOGIC_HIERARCHY_MEMORY_UNSUPPORTED",
                    message: "Hierarchy elaboration cannot flatten a module containing memories into the native execution profile.",
                    entity: module.name,
                    actions: ["lower_memory_to_supported_storage", "use_memory_aware_backend"]
                ))
                return
            }
            guard module.generateBlocks.isEmpty else {
                diagnostics.append(diagnostic(
                    code: "LOGIC_HIERARCHY_GENERATE_UNELABORATED",
                    message: "Hierarchy elaboration requires constant generate blocks to be expanded first.",
                    entity: module.name,
                    actions: ["run_generate_elaboration", "resolve_generate_conditions"]
                ))
                return
            }

            for instance in module.instances {
                flatten(
                    instance: instance,
                    parentMapping: mapping,
                    prefix: prefix + instance.instanceName + "__",
                    path: path + [instance.instanceName],
                    into: &flattenedTop
                )
            }
        }

        mutating func flatten(
            instance: RTLInstance,
            parentMapping: [String: RTLExpression],
            prefix: String,
            path: [String],
            into flattenedTop: inout RTLModule
        ) {
            guard instance.parameterOverrides.isEmpty else {
                diagnostics.append(diagnostic(
                    code: "LOGIC_HIERARCHY_PARAMETER_OVERRIDE_UNSUPPORTED",
                    message: "Instance parameter overrides require parameter-aware hierarchy elaboration.",
                    entity: path.joined(separator: "."),
                    location: instance.source,
                    actions: ["elaborate_instance_parameters", "remove_parameter_override"]
                ))
                return
            }
            guard let child = modulesByName[instance.moduleName]?.first else {
                diagnostics.append(diagnostic(
                    code: "LOGIC_HIERARCHY_INSTANCE_UNRESOLVED",
                    message: "Hierarchy instance references a module that is not defined.",
                    entity: path.joined(separator: "."),
                    location: instance.source,
                    actions: ["add_referenced_module", "correct_instance_type"]
                ))
                return
            }
            guard !path.dropLast().contains(child.name) else {
                diagnostics.append(diagnostic(
                    code: "LOGIC_HIERARCHY_CYCLE",
                    message: "The module hierarchy contains a recursive instance cycle.",
                    entity: (path + [child.name]).joined(separator: "."),
                    location: instance.source,
                    actions: ["remove_recursive_instance", "replace_with_sequential_boundary"]
                ))
                return
            }

            let connections = connectionMap(
                instance.connections,
                ports: child.ports,
                entity: path.joined(separator: ".")
            )
            guard connections != nil else { return }

            var childMapping: [String: RTLExpression] = [:]
            for port in child.ports {
                guard let connection = connections?[port.name] else {
                    if port.direction == .output {
                        let localName = prefix + port.name
                        addSignal(
                            name: localName,
                            port: port,
                            instancePath: path,
                            into: &flattenedTop
                        )
                        childMapping[port.name] = .identifier(localName)
                        continue
                    }
                    diagnostics.append(diagnostic(
                        code: "LOGIC_HIERARCHY_UNCONNECTED_PORT",
                        message: "Every non-output hierarchy port must have a connection in the native elaboration profile.",
                        entity: "\(path.joined(separator: ".")).\(port.name)",
                        location: port.source,
                        actions: ["connect_instance_port", "use_an_external_elaborator"]
                    ))
                    continue
                }
                let expression = rewrite(connection.expression, mapping: parentMapping)
                switch port.direction {
                case .input:
                    childMapping[port.name] = inputMapping(
                        expression,
                        port: port,
                        prefix: prefix,
                        instancePath: path,
                        into: &flattenedTop
                    )
                case .output:
                    let localName = prefix + port.name
                    addSignal(
                        name: localName,
                        port: port,
                        instancePath: path,
                        into: &flattenedTop
                    )
                    childMapping[port.name] = .identifier(localName)
                    guard case .identifier(let target) = expression else {
                        diagnostics.append(diagnostic(
                            code: "LOGIC_HIERARCHY_OUTPUT_CONNECTION_UNSUPPORTED",
                            message: "Native hierarchy flattening requires output connections to be identifiers.",
                            entity: "\(path.joined(separator: ".")).\(port.name)",
                            location: connection.source,
                            actions: ["connect_output_to_named_signal", "use_an_external_elaborator"]
                        ))
                        continue
                    }
                    flattenedTop.assignments.append(RTLAssignment(
                        id: stableID(kind: "hierarchical-output", path: path, name: port.name),
                        target: .identifier(target),
                        value: .identifier(localName),
                        source: connection.source
                    ))
                case .inOut, .internalSignal:
                    diagnostics.append(diagnostic(
                        code: "LOGIC_HIERARCHY_INOUT_UNSUPPORTED",
                        message: "Inout and internal-direction hierarchy ports require a resolved bidirectional net model.",
                        entity: "\(path.joined(separator: ".")).\(port.name)",
                        location: port.source,
                        actions: ["use_explicit_tri_state_model", "use_an_external_elaborator"]
                    ))
                }
            }

            for signal in child.signals {
                let localName = prefix + signal.name
                addSignal(
                    name: localName,
                    signal: signal,
                    instancePath: path,
                    into: &flattenedTop
                )
                childMapping[signal.name] = .identifier(localName)
            }

            let childAssignments = child.assignments.map { assignment in
                RTLAssignment(
                    id: stableID(kind: "hierarchical-assignment", path: path, name: assignment.id),
                    target: rewrite(assignment.target, mapping: childMapping),
                    value: rewrite(assignment.value, mapping: childMapping),
                    nonBlocking: assignment.nonBlocking,
                    source: assignment.source
                )
            }
            flattenedTop.assignments.append(contentsOf: childAssignments)
            flattenedTop.processes.append(contentsOf: child.processes.map { process in
                RTLProcess(
                    id: stableID(kind: "hierarchical-process", path: path, name: process.id),
                    kind: process.kind,
                    sensitivity: process.sensitivity.map { sensitivity in
                        if case .identifier(let name) = childMapping[sensitivity] {
                            return name
                        }
                        return sensitivity
                    },
                    clockEdge: process.clockEdge,
                    statements: process.statements.map { rewrite($0, mapping: childMapping) },
                    source: process.source
                )
            })

            flattenInstances(
                in: child,
                prefix: prefix,
                mapping: childMapping,
                path: path,
                into: &flattenedTop
            )
        }

        mutating func connectionMap(
            _ connections: [RTLPortConnection],
            ports: [RTLPort],
            entity: String
        ) -> [String: RTLPortConnection]? {
            var result: [String: RTLPortConnection] = [:]
            for (index, connection) in connections.enumerated() {
                let portName: String
                if let positionalIndex = Int(connection.portName) {
                    guard positionalIndex >= 0, positionalIndex < ports.count else {
                        diagnostics.append(diagnostic(
                            code: "LOGIC_HIERARCHY_CONNECTION_INDEX_INVALID",
                            message: "A positional hierarchy connection does not refer to a declared port.",
                            entity: entity,
                            location: connection.source,
                            actions: ["correct_positional_connection", "use_named_connection"]
                        ))
                        continue
                    }
                    portName = ports[positionalIndex].name
                } else {
                    portName = connection.portName
                }
                guard ports.contains(where: { $0.name == portName }) else {
                    diagnostics.append(diagnostic(
                        code: "LOGIC_HIERARCHY_PORT_UNRESOLVED",
                        message: "A hierarchy connection refers to an undeclared child port.",
                        entity: "\(entity).\(portName)",
                        location: connection.source,
                        actions: ["correct_port_name", "use_positional_connection"]
                    ))
                    continue
                }
                guard result[portName] == nil else {
                    diagnostics.append(diagnostic(
                        code: "LOGIC_HIERARCHY_PORT_DUPLICATE_CONNECTION",
                        message: "A child port has more than one hierarchy connection.",
                        entity: "\(entity).\(portName)",
                        location: connection.source,
                        actions: ["remove_duplicate_connection"]
                    ))
                    continue
                }
                result[portName] = connection
                _ = index
            }
            return diagnostics.contains { $0.severity == .error } ? nil : result
        }

        mutating func inputMapping(
            _ expression: RTLExpression,
            port: RTLPort,
            prefix: String,
            instancePath: [String],
            into flattenedTop: inout RTLModule
        ) -> RTLExpression {
            if case .identifier = expression {
                return expression
            }
            let alias = prefix + port.name + "__input"
            addSignal(
                name: alias,
                port: port,
                instancePath: instancePath,
                into: &flattenedTop
            )
            flattenedTop.assignments.append(RTLAssignment(
                id: stableID(kind: "hierarchical-input", path: instancePath, name: port.name),
                target: .identifier(alias),
                value: expression,
                source: port.source
            ))
            return .identifier(alias)
        }

        mutating func addSignal(
            name: String,
            port: RTLPort,
            instancePath: [String],
            into flattenedTop: inout RTLModule
        ) {
            addSignal(
                name: name,
                range: port.range,
                dataType: port.dataType,
                storage: .net,
                isSigned: port.isSigned,
                source: port.source,
                instancePath: instancePath,
                into: &flattenedTop
            )
        }

        mutating func addSignal(
            name: String,
            signal: RTLSignal,
            instancePath: [String],
            into flattenedTop: inout RTLModule
        ) {
            addSignal(
                name: name,
                range: signal.range,
                dataType: signal.dataType,
                storage: signal.storage,
                isSigned: signal.isSigned,
                source: signal.source,
                instancePath: instancePath,
                into: &flattenedTop
            )
        }

        mutating func addSignal(
            name: String,
            range: LogicRange?,
            dataType: LogicDataType,
            storage: LogicStorageKind,
            isSigned: Bool,
            source: LogicSourceSpan?,
            instancePath: [String],
            into flattenedTop: inout RTLModule
        ) {
            let existingPort = flattenedTop.ports.first(where: { $0.name == name })
            let existingSignal = flattenedTop.signals.first(where: { $0.name == name })
            if let existingPort {
                if existingPort.range != range || existingPort.isSigned != isSigned {
                    diagnostics.append(diagnostic(
                        code: "LOGIC_HIERARCHY_SIGNAL_COLLISION",
                        message: "Flattened hierarchy signal collides with a top-level port.",
                        entity: name,
                        actions: ["rename_top_level_signal", "use_an_external_elaborator"]
                    ))
                }
                return
            }
            if let existingSignal {
                if existingSignal.range != range || existingSignal.isSigned != isSigned {
                    diagnostics.append(diagnostic(
                        code: "LOGIC_HIERARCHY_SIGNAL_COLLISION",
                        message: "Flattened hierarchy signals have conflicting width or signedness.",
                        entity: name,
                        actions: ["rename_instance_signal", "use_an_external_elaborator"]
                    ))
                }
                return
            }
            flattenedTop.signals.append(RTLSignal(
                id: stableID(kind: "hierarchical-signal", path: instancePath, name: name),
                name: name,
                dataType: dataType,
                storage: storage,
                range: range,
                isSigned: isSigned,
                source: source
            ))
        }

        func rewrite(
            _ expression: RTLExpression,
            mapping: [String: RTLExpression]
        ) -> RTLExpression {
            switch expression {
            case .identifier(let name):
                return mapping[name] ?? expression
            case .integer, .string:
                return expression
            case .unary(let operation, let operand):
                return .unary(operator: operation, operand: rewrite(operand, mapping: mapping))
            case .binary(let operation, let left, let right):
                return .binary(
                    operator: operation,
                    left: rewrite(left, mapping: mapping),
                    right: rewrite(right, mapping: mapping)
                )
            case .ternary(let condition, let ifTrue, let ifFalse):
                return .ternary(
                    condition: rewrite(condition, mapping: mapping),
                    ifTrue: rewrite(ifTrue, mapping: mapping),
                    ifFalse: rewrite(ifFalse, mapping: mapping)
                )
            case .concatenate(let values):
                return .concatenate(values.map { rewrite($0, mapping: mapping) })
            case .index(let value, let index):
                return .index(
                    value: rewrite(value, mapping: mapping),
                    index: rewrite(index, mapping: mapping)
                )
            case .partSelect(let value, let msb, let lsb):
                return .partSelect(
                    value: rewrite(value, mapping: mapping),
                    msb: rewrite(msb, mapping: mapping),
                    lsb: rewrite(lsb, mapping: mapping)
                )
            }
        }

        func rewrite(
            _ statement: RTLStatement,
            mapping: [String: RTLExpression]
        ) -> RTLStatement {
            switch statement {
            case .assignment(let assignment):
                return .assignment(RTLAssignment(
                    id: assignment.id,
                    target: rewrite(assignment.target, mapping: mapping),
                    value: rewrite(assignment.value, mapping: mapping),
                    nonBlocking: assignment.nonBlocking,
                    source: assignment.source
                ))
            case .block(let statements):
                return .block(statements.map { rewrite($0, mapping: mapping) })
            case .conditional(let condition, let ifTrue, let ifFalse):
                return .conditional(
                    condition: rewrite(condition, mapping: mapping),
                    ifTrue: ifTrue.map { rewrite($0, mapping: mapping) },
                    ifFalse: ifFalse.map { rewrite($0, mapping: mapping) }
                )
            case .caseStatement(let expression, let items, let defaults):
                return .caseStatement(
                    expression: rewrite(expression, mapping: mapping),
                    items: items.map { rewrite($0, mapping: mapping) },
                    defaultStatements: defaults.map { rewrite($0, mapping: mapping) }
                )
            case .typedCaseStatement(let kind, let expression, let items, let defaults):
                return .typedCaseStatement(
                    kind: kind,
                    expression: rewrite(expression, mapping: mapping),
                    items: items.map { rewrite($0, mapping: mapping) },
                    defaultStatements: defaults.map { rewrite($0, mapping: mapping) }
                )
            case .null:
                return .null
            }
        }

        func rewrite(
            _ item: RTLCaseItem,
            mapping: [String: RTLExpression]
        ) -> RTLCaseItem {
            RTLCaseItem(
                matches: item.matches.map { rewrite($0, mapping: mapping) },
                statements: item.statements.map { rewrite($0, mapping: mapping) },
                source: item.source
            )
        }

        func stableID(kind: String, path: [String], name: String) -> String {
            StableLogicID.make(
                kind: kind,
                path: topModuleName + "/" + path.joined(separator: "/"),
                name: name
            )
        }

        private func diagnostic(
            code: String,
            message: String,
            entity: String? = nil,
            location: LogicSourceSpan? = nil,
            actions: [String]
        ) -> LogicDiagnostic {
            LogicDiagnostic(
                severity: .error,
                code: code,
                message: message,
                entity: entity,
                location: location,
                suggestedActions: actions
            )
        }
    }

    private func diagnostic(
        code: String,
        message: String,
        entity: String? = nil,
        location: LogicSourceSpan? = nil,
        actions: [String]
    ) -> LogicDiagnostic {
        LogicDiagnostic(
            severity: .error,
            code: code,
            message: message,
            entity: entity,
            location: location,
            suggestedActions: actions
        )
    }
}
