import CircuiteFoundation

public struct LogicDataflowValidator: LogicDataflowValidating {
    public init() {}

    public func validate(_ design: LogicDataflowDesign) -> LogicValidationResult {
        var diagnostics: [LogicDiagnostic] = []
        validateIdentifier(design.packageName, role: "package", diagnostics: &diagnostics)

        let functionNames = design.functions.map(\.name)
        let processNames = design.processes.map(\.name)
        let entityNames = functionNames + processNames
        appendDuplicateDiagnostic(
            values: entityNames,
            code: "DATAFLOW_DUPLICATE_ENTITY",
            message: "Function and process names must be unique.",
            diagnostics: &diagnostics
        )
        if let topEntityName = design.topEntityName,
           !entityNames.contains(topEntityName) {
            diagnostics.append(error(
                code: "DATAFLOW_TOP_UNRESOLVED",
                message: "The selected top entity is not defined.",
                entity: topEntityName,
                action: "select_existing_top_entity"
            ))
        }

        let channelNames = design.channels.map(\.name)
        appendDuplicateDiagnostic(
            values: channelNames,
            code: "DATAFLOW_DUPLICATE_CHANNEL",
            message: "Channel names must be unique.",
            diagnostics: &diagnostics
        )
        let channelIDs = design.channels.map(\.id)
        if Set(channelIDs).count != channelIDs.count {
            diagnostics.append(error(
                code: "DATAFLOW_DUPLICATE_CHANNEL_ID",
                message: "Channel numeric identities must be unique.",
                action: "assign_unique_channel_ids"
            ))
        }

        var channelsByID: [UInt64: LogicDataflowChannel] = [:]
        var channelsByName: [String: LogicDataflowChannel] = [:]
        for channel in design.channels {
            validateIdentifier(channel.name, role: "channel", diagnostics: &diagnostics)
            validateType(channel.type, entity: channel.name, diagnostics: &diagnostics)
            if channel.kind == .streaming && channel.flowControl == nil {
                diagnostics.append(error(
                    code: "DATAFLOW_CHANNEL_FLOW_CONTROL_MISSING",
                    message: "A streaming channel requires an explicit flow-control contract.",
                    entity: channel.name,
                    action: "declare_channel_flow_control"
                ))
            }
            for initialValue in channel.initialValues where !initialValue.matches(channel.type) {
                diagnostics.append(error(
                    code: "DATAFLOW_CHANNEL_INITIAL_VALUE_TYPE_MISMATCH",
                    message: "A channel initial value does not match the channel type.",
                    entity: channel.name,
                    action: "repair_channel_initial_value"
                ))
            }
            if channel.kind != .streaming,
               channel.strictness != nil || channel.fifoConfiguration != nil {
                diagnostics.append(error(
                    code: "DATAFLOW_CHANNEL_CONFIGURATION_INVALID",
                    message: "Strictness and FIFO configuration apply only to streaming channels.",
                    entity: channel.name,
                    action: "repair_channel_configuration"
                ))
            }
            if let fifoConfiguration = channel.fifoConfiguration {
                if let depth = fifoConfiguration.depth, depth <= 0 {
                    diagnostics.append(error(
                        code: "DATAFLOW_CHANNEL_FIFO_DEPTH_INVALID",
                        message: "FIFO depth must be greater than zero when declared.",
                        entity: channel.name,
                        action: "repair_fifo_depth"
                    ))
                }
                if let implementationName = fifoConfiguration.implementationName,
                   implementationName.isEmpty {
                    diagnostics.append(error(
                        code: "DATAFLOW_CHANNEL_FIFO_IMPLEMENTATION_INVALID",
                        message: "FIFO implementation names must not be empty.",
                        entity: channel.name,
                        action: "repair_fifo_implementation_name"
                    ))
                }
            }
            channelsByID[channel.id] = channel
            channelsByName[channel.name] = channel
        }

        for function in design.functions {
            validateFunction(
                function,
                channelsByID: channelsByID,
                channelsByName: channelsByName,
                diagnostics: &diagnostics
            )
        }
        for process in design.processes {
            validateProcess(
                process,
                channelsByID: channelsByID,
                channelsByName: channelsByName,
                diagnostics: &diagnostics
            )
        }

        return LogicValidationResult(
            isValid: !diagnostics.contains { $0.severity == .error },
            diagnostics: diagnostics
        )
    }

    private func validateFunction(
        _ function: LogicDataflowFunction,
        channelsByID: [UInt64: LogicDataflowChannel],
        channelsByName: [String: LogicDataflowChannel],
        diagnostics: inout [LogicDiagnostic]
    ) {
        validateIdentifier(function.name, role: "function", diagnostics: &diagnostics)
        validateType(function.returnType, entity: function.name, diagnostics: &diagnostics)
        var symbols: [String: LogicDataflowType] = [:]
        var externalIDs = Set<UInt64>()
        for parameter in function.parameters {
            validateIdentifier(parameter.name, role: "parameter", diagnostics: &diagnostics)
            validateType(parameter.type, entity: "\(function.name).\(parameter.name)", diagnostics: &diagnostics)
            insertSymbol(
                parameter.name,
                type: parameter.type,
                owner: function.name,
                symbols: &symbols,
                diagnostics: &diagnostics
            )
            if let externalNumericID = parameter.externalNumericID,
               !externalIDs.insert(externalNumericID).inserted {
                diagnostics.append(error(
                    code: "DATAFLOW_DUPLICATE_EXTERNAL_NODE_ID",
                    message: "External node identities must be unique within an entity.",
                    entity: "\(function.name).\(parameter.name)",
                    action: "assign_unique_external_node_ids"
                ))
            }
        }
        validateNodes(
            function.nodes,
            owner: function.name,
            symbols: &symbols,
            stateElements: [:],
            externalIDs: &externalIDs,
            channelsByID: channelsByID,
            channelsByName: channelsByName,
            diagnostics: &diagnostics
        )
        guard let returnType = symbols[function.returnValue] else {
            diagnostics.append(error(
                code: "DATAFLOW_RETURN_UNRESOLVED",
                message: "The function return value is not defined.",
                entity: "\(function.name).\(function.returnValue)",
                action: "return_defined_value"
            ))
            return
        }
        if returnType != function.returnType {
            diagnostics.append(error(
                code: "DATAFLOW_RETURN_TYPE_MISMATCH",
                message: "The function return value does not match its declared return type.",
                entity: function.name,
                action: "repair_return_type"
            ))
        }
    }

    private func validateProcess(
        _ process: LogicDataflowProcess,
        channelsByID: [UInt64: LogicDataflowChannel],
        channelsByName: [String: LogicDataflowChannel],
        diagnostics: inout [LogicDiagnostic]
    ) {
        validateIdentifier(process.name, role: "process", diagnostics: &diagnostics)
        var stateElements: [String: LogicDataflowStateElement] = [:]
        var symbols: [String: LogicDataflowType] = [:]
        var externalIDs = Set<UInt64>()
        for stateElement in process.stateElements {
            validateIdentifier(stateElement.name, role: "state element", diagnostics: &diagnostics)
            validateType(
                stateElement.type,
                entity: "\(process.name).\(stateElement.name)",
                diagnostics: &diagnostics
            )
            if !stateElement.initialValue.matches(stateElement.type) {
                diagnostics.append(error(
                    code: "DATAFLOW_STATE_INITIAL_VALUE_TYPE_MISMATCH",
                    message: "A process state initial value does not match its declared type.",
                    entity: "\(process.name).\(stateElement.name)",
                    action: "repair_state_initial_value"
                ))
            }
            if stateElements.updateValue(stateElement, forKey: stateElement.name) != nil {
                diagnostics.append(error(
                    code: "DATAFLOW_DUPLICATE_STATE_ELEMENT",
                    message: "Process state element names must be unique.",
                    entity: "\(process.name).\(stateElement.name)",
                    action: "rename_duplicate_state_element"
                ))
            }
        }
        validateNodes(
            process.nodes,
            owner: process.name,
            symbols: &symbols,
            stateElements: stateElements,
            externalIDs: &externalIDs,
            channelsByID: channelsByID,
            channelsByName: channelsByName,
            diagnostics: &diagnostics
        )

        if !process.nextStateValues.isEmpty {
            if process.nextStateValues.count != process.stateElements.count {
                diagnostics.append(error(
                    code: "DATAFLOW_NEXT_STATE_ARITY_MISMATCH",
                    message: "The process next-state tuple must provide one value per state element.",
                    entity: process.name,
                    action: "repair_next_state_arity"
                ))
            }
            for (stateElement, nextValueName) in zip(process.stateElements, process.nextStateValues) {
                guard let nextValueType = symbols[nextValueName] else {
                    diagnostics.append(error(
                        code: "DATAFLOW_NEXT_STATE_UNRESOLVED",
                        message: "A process next-state value is not defined.",
                        entity: "\(process.name).\(nextValueName)",
                        action: "define_next_state_value"
                    ))
                    continue
                }
                if nextValueType != stateElement.type {
                    diagnostics.append(error(
                        code: "DATAFLOW_NEXT_STATE_TYPE_MISMATCH",
                        message: "A process next-state value does not match its state element type.",
                        entity: "\(process.name).\(stateElement.name)",
                        action: "repair_next_state_type"
                    ))
                }
            }
        } else if !process.stateElements.isEmpty
                    && !process.nodes.contains(where: { $0.operation.kind == .nextValue }) {
            diagnostics.append(error(
                code: "DATAFLOW_NEXT_STATE_MISSING",
                message: "A stateful process requires a next-state contract.",
                entity: process.name,
                action: "define_next_state_values"
            ))
        }
    }

    private func validateNodes(
        _ nodes: [LogicDataflowNode],
        owner: String,
        symbols: inout [String: LogicDataflowType],
        stateElements: [String: LogicDataflowStateElement],
        externalIDs: inout Set<UInt64>,
        channelsByID: [UInt64: LogicDataflowChannel],
        channelsByName: [String: LogicDataflowChannel],
        diagnostics: inout [LogicDiagnostic]
    ) {
        for node in nodes {
            validateIdentifier(node.name, role: "node", diagnostics: &diagnostics)
            validateType(node.type, entity: "\(owner).\(node.name)", diagnostics: &diagnostics)
            if !LogicDataflowOperationKind.supportedCanonicalKinds.contains(node.operation.kind) {
                diagnostics.append(error(
                    code: "DATAFLOW_OPERATION_UNSUPPORTED",
                    message: "The canonical dataflow operation is not supported.",
                    entity: "\(owner).\(node.name):\(node.operation.kind.rawValue)",
                    action: "add_operation_semantics"
                ))
            }
            if let externalNumericID = node.externalNumericID,
               !externalIDs.insert(externalNumericID).inserted {
                diagnostics.append(error(
                    code: "DATAFLOW_DUPLICATE_EXTERNAL_NODE_ID",
                    message: "External node identities must be unique within an entity.",
                    entity: "\(owner).\(node.name)",
                    action: "assign_unique_external_node_ids"
                ))
            }
            let attributeNames = node.operation.attributes.map(\.name)
            appendDuplicateDiagnostic(
                values: attributeNames,
                code: "DATAFLOW_DUPLICATE_OPERATION_ATTRIBUTE",
                message: "Operation attribute names must be unique.",
                entity: "\(owner).\(node.name)",
                diagnostics: &diagnostics
            )
            for operand in node.operation.operands where symbols[operand] == nil {
                diagnostics.append(error(
                    code: "DATAFLOW_OPERAND_UNRESOLVED",
                    message: "An operation operand is not defined before use.",
                    entity: "\(owner).\(node.name).\(operand)",
                    action: "define_operand_before_use"
                ))
            }
            validateOperation(
                node,
                owner: owner,
                symbols: symbols,
                stateElements: stateElements,
                channelsByID: channelsByID,
                channelsByName: channelsByName,
                diagnostics: &diagnostics
            )
            insertSymbol(
                node.name,
                type: node.type,
                owner: owner,
                symbols: &symbols,
                diagnostics: &diagnostics
            )
        }
    }

    private func validateOperation(
        _ node: LogicDataflowNode,
        owner: String,
        symbols: [String: LogicDataflowType],
        stateElements: [String: LogicDataflowStateElement],
        channelsByID: [UInt64: LogicDataflowChannel],
        channelsByName: [String: LogicDataflowChannel],
        diagnostics: inout [LogicDiagnostic]
    ) {
        let kind = node.operation.kind
        let operandTypes = node.operation.operands.compactMap { symbols[$0] }
        let entity = "\(owner).\(node.name)"

        if kind == .literal {
            guard node.operation.operands.isEmpty,
                  case .literal(let value)? = attribute(named: "value", in: node.operation),
                  value.matches(node.type) else {
                diagnostics.append(operationError(entity: entity, contract: "literal value and result type"))
                return
            }
        } else if kind == .identity {
            require(
                operandTypes.count == 1 && operandTypes.first == node.type,
                entity: entity,
                contract: "one operand matching the result type",
                diagnostics: &diagnostics
            )
        } else if [.bitwiseNot, .negate, .reverseBits].contains(kind) {
            let resultIsBits: Bool
            if case .bits = node.type {
                resultIsBits = true
            } else {
                resultIsBits = false
            }
            require(
                resultIsBits
                    && operandTypes.count == 1
                    && operandTypes.first == node.type
                    && node.operation.operands.count == 1,
                entity: entity,
                contract: "one bits operand matching the result type",
                diagnostics: &diagnostics
            )
        } else if [
            .bitwiseAnd,
            .bitwiseNand,
            .bitwiseOr,
            .bitwiseNor,
            .bitwiseXor,
        ].contains(kind) {
            let resultIsBits: Bool
            if case .bits = node.type {
                resultIsBits = true
            } else {
                resultIsBits = false
            }
            require(
                resultIsBits
                    && !operandTypes.isEmpty
                    && operandTypes.count == node.operation.operands.count
                    && operandTypes.allSatisfy { $0 == node.type },
                entity: entity,
                contract: "one or more identically typed bits operands matching the result type",
                diagnostics: &diagnostics
            )
        } else if [.reduceAnd, .reduceOr, .reduceXor].contains(kind) {
            let operandIsBits: Bool
            if operandTypes.count == 1, case .bits = operandTypes[0] {
                operandIsBits = true
            } else {
                operandIsBits = false
            }
            require(
                operandIsBits
                    && node.operation.operands.count == 1
                    && node.type == .bits(width: 1),
                entity: entity,
                contract: "one bits operand and a one-bit result",
                diagnostics: &diagnostics
            )
        } else if [.add, .subtract, .signedDivide, .unsignedDivide, .signedModulo, .unsignedModulo]
                    .contains(kind) {
            let resultIsBits: Bool
            if case .bits = node.type {
                resultIsBits = true
            } else {
                resultIsBits = false
            }
            require(
                resultIsBits
                    && operandTypes.count == 2
                    && node.operation.operands.count == 2
                    && operandTypes.allSatisfy { $0 == node.type },
                entity: entity,
                contract: "two bits operands matching the result type",
                diagnostics: &diagnostics
            )
        } else if [.signedMultiply, .unsignedMultiply].contains(kind) {
            let operandsAndResultAreBits: Bool
            if operandTypes.count == 2,
               case .bits = operandTypes[0],
               case .bits = operandTypes[1],
               case .bits = node.type {
                operandsAndResultAreBits = true
            } else {
                operandsAndResultAreBits = false
            }
            require(
                operandsAndResultAreBits && node.operation.operands.count == 2,
                entity: entity,
                contract: "two bits operands and a bits result",
                diagnostics: &diagnostics
            )
        } else if [.equal, .notEqual].contains(kind) {
            require(
                operandTypes.count == 2
                    && node.operation.operands.count == 2
                    && operandTypes[0] == operandTypes[1]
                    && node.type == .bits(width: 1),
                entity: entity,
                contract: "two identically typed operands and a one-bit result",
                diagnostics: &diagnostics
            )
        } else if [
            .signedGreaterThanOrEqual,
            .signedGreaterThan,
            .signedLessThanOrEqual,
            .signedLessThan,
            .unsignedGreaterThanOrEqual,
            .unsignedGreaterThan,
            .unsignedLessThanOrEqual,
            .unsignedLessThan,
        ].contains(kind) {
            let matchingBitsOperands: Bool
            if operandTypes.count == 2,
               operandTypes[0] == operandTypes[1],
               case .bits = operandTypes[0] {
                matchingBitsOperands = true
            } else {
                matchingBitsOperands = false
            }
            require(
                matchingBitsOperands
                    && node.operation.operands.count == 2
                    && node.type == .bits(width: 1),
                entity: entity,
                contract: "two identically typed bits operands and a one-bit result",
                diagnostics: &diagnostics
            )
        } else if [.shiftLeftLogical, .shiftRightArithmetic, .shiftRightLogical].contains(kind) {
            let shiftTypesMatch: Bool
            if operandTypes.count == 2,
               operandTypes[0] == node.type,
               case .bits = operandTypes[0],
               case .bits = operandTypes[1] {
                shiftTypesMatch = true
            } else {
                shiftTypesMatch = false
            }
            require(
                shiftTypesMatch && node.operation.operands.count == 2,
                entity: entity,
                contract: "a bits value, a bits shift amount, and a result matching the shifted value",
                diagnostics: &diagnostics
            )
        } else if kind == .concatenate {
            let widths = operandTypes.compactMap { type -> Int? in
                guard case .bits(let width) = type else { return nil }
                return width
            }
            let expectedWidth = widths.reduce(0, +)
            require(
                widths.count == operandTypes.count
                    && operandTypes.count == node.operation.operands.count
                    && node.type == .bits(width: expectedWidth),
                entity: entity,
                contract: "bit operands whose widths sum to the result width",
                diagnostics: &diagnostics
            )
        } else if kind == .tuple {
            require(
                node.type == .tuple(operandTypes)
                    && operandTypes.count == node.operation.operands.count,
                entity: entity,
                contract: "a tuple result matching the ordered operand types",
                diagnostics: &diagnostics
            )
        } else if kind == .tupleIndex {
            let index: Int?
            if case .integer(let rawIndex)? = attribute(named: "index", in: node.operation),
               rawIndex >= 0,
               let convertedIndex = Int(exactly: rawIndex) {
                index = convertedIndex
            } else {
                index = nil
            }
            let expectedType: LogicDataflowType?
            if operandTypes.count == 1,
               case .tuple(let elements) = operandTypes[0],
               let index,
               elements.indices.contains(index) {
                expectedType = elements[index]
            } else {
                expectedType = nil
            }
            require(
                expectedType == node.type,
                entity: entity,
                contract: "one tuple operand and an in-range integer index",
                diagnostics: &diagnostics
            )
        } else if kind == .afterAll {
            require(
                node.type == .token
                    && operandTypes.count == node.operation.operands.count
                    && operandTypes.allSatisfy { $0 == .token },
                entity: entity,
                contract: "token operands and a token result",
                diagnostics: &diagnostics
            )
        } else if kind == .stateRead {
            let stateElement = referencedIdentifier(named: "state_element", in: node.operation)
                .flatMap { stateElements[$0] }
            let predicateType = referencedIdentifier(named: "predicate", in: node.operation)
                .flatMap { symbols[$0] }
            require(
                node.operation.operands.isEmpty
                    && stateElement?.type == node.type
                    && (predicateType == nil || predicateType == .bits(width: 1)),
                entity: entity,
                contract: "an existing state element and an optional one-bit predicate",
                diagnostics: &diagnostics
            )
        } else if kind == .nextValue {
            let stateElement = referencedIdentifier(named: "state_element", in: node.operation)
                .flatMap { stateElements[$0] }
            let valueType = referencedIdentifier(named: "value", in: node.operation)
                .flatMap { symbols[$0] }
            let predicateType = referencedIdentifier(named: "predicate", in: node.operation)
                .flatMap { symbols[$0] }
            require(
                node.type == .tuple([])
                    && stateElement?.type == valueType
                    && (predicateType == nil || predicateType == .bits(width: 1)),
                entity: entity,
                contract: "matching state/value references, an optional one-bit predicate, and a unit result",
                diagnostics: &diagnostics
            )
        } else if kind == .send || kind == .receive {
            validateChannelOperation(
                node,
                operandTypes: operandTypes,
                channelsByID: channelsByID,
                channelsByName: channelsByName,
                diagnostics: &diagnostics,
                entity: entity
            )
        }
    }

    private func validateChannelOperation(
        _ node: LogicDataflowNode,
        operandTypes: [LogicDataflowType],
        channelsByID: [UInt64: LogicDataflowChannel],
        channelsByName: [String: LogicDataflowChannel],
        diagnostics: inout [LogicDiagnostic],
        entity: String
    ) {
        let channelByID: LogicDataflowChannel?
        switch attribute(named: "channel_id", in: node.operation) {
        case .unsignedInteger(let value):
            channelByID = channelsByID[value]
        case .integer(let value) where value >= 0:
            channelByID = UInt64(exactly: value).flatMap { channelsByID[$0] }
        default:
            channelByID = nil
        }
        let channelByName: LogicDataflowChannel?
        if case .identifier(let name)? = attribute(named: "channel", in: node.operation) {
            channelByName = channelsByName[name]
        } else {
            channelByName = nil
        }
        guard (channelByID == nil) != (channelByName == nil),
              let channel = channelByID ?? channelByName else {
            diagnostics.append(operationError(
                entity: entity,
                contract: "exactly one existing channel or non-negative channel_id reference"
            ))
            return
        }
        if node.operation.kind == .send {
            let acceptsSend = channel.operations == .sendOnly || channel.operations == .sendReceive
            let contractMatches = acceptsSend
                && (operandTypes.count == 2 || operandTypes.count == 3)
                && operandTypes.first == .token
                && operandTypes.last == channel.type
                && (operandTypes.count != 3 || operandTypes[1] == .bits(width: 1))
                && node.type == .token
            require(
                contractMatches,
                entity: entity,
                contract: "a send-capable channel, token, optional predicate, data, and token result",
                diagnostics: &diagnostics
            )
        } else {
            let acceptsReceive = channel.operations == .receiveOnly || channel.operations == .sendReceive
            let contractMatches = acceptsReceive
                && (operandTypes.count == 1 || operandTypes.count == 2)
                && operandTypes.first == .token
                && (operandTypes.count != 2 || operandTypes[1] == .bits(width: 1))
                && node.type == .tuple([.token, channel.type])
            require(
                contractMatches,
                entity: entity,
                contract: "a receive-capable channel, token, optional predicate, and token-data tuple result",
                diagnostics: &diagnostics
            )
        }
    }

    private func validateType(
        _ type: LogicDataflowType,
        entity: String,
        diagnostics: inout [LogicDiagnostic]
    ) {
        if !type.isValid {
            diagnostics.append(error(
                code: "DATAFLOW_TYPE_INVALID",
                message: "A dataflow type has an invalid width or array count.",
                entity: entity,
                action: "repair_dataflow_type"
            ))
        }
    }

    private func validateIdentifier(
        _ value: String,
        role: String,
        diagnostics: inout [LogicDiagnostic]
    ) {
        guard let first = value.first,
              first.isLetter || first == "_",
              value.allSatisfy({ $0.isLetter || $0.isNumber || "_.$".contains($0) }) else {
            diagnostics.append(error(
                code: "DATAFLOW_IDENTIFIER_INVALID",
                message: "A \(role) identifier is empty or contains unsupported characters.",
                entity: value,
                action: "repair_identifier"
            ))
            return
        }
    }

    private func insertSymbol(
        _ name: String,
        type: LogicDataflowType,
        owner: String,
        symbols: inout [String: LogicDataflowType],
        diagnostics: inout [LogicDiagnostic]
    ) {
        if symbols.updateValue(type, forKey: name) != nil {
            diagnostics.append(error(
                code: "DATAFLOW_DUPLICATE_SYMBOL",
                message: "Dataflow symbols must be unique within an entity.",
                entity: "\(owner).\(name)",
                action: "rename_duplicate_symbol"
            ))
        }
    }

    private func appendDuplicateDiagnostic<Value: Hashable>(
        values: [Value],
        code: String,
        message: String,
        entity: String? = nil,
        diagnostics: inout [LogicDiagnostic]
    ) {
        if Set(values).count != values.count {
            diagnostics.append(error(
                code: code,
                message: message,
                entity: entity,
                action: "remove_duplicate_values"
            ))
        }
    }

    private func attribute(
        named name: String,
        in operation: LogicDataflowOperation
    ) -> LogicDataflowAttributeValue? {
        operation.attributes.first { $0.name == name }?.value
    }

    private func referencedIdentifier(
        named name: String,
        in operation: LogicDataflowOperation
    ) -> String? {
        guard case .identifier(let value)? = attribute(named: name, in: operation) else {
            return nil
        }
        return value
    }

    private func require(
        _ condition: Bool,
        entity: String,
        contract: String,
        diagnostics: inout [LogicDiagnostic]
    ) {
        if !condition {
            diagnostics.append(operationError(entity: entity, contract: contract))
        }
    }

    private func operationError(entity: String, contract: String) -> LogicDiagnostic {
        error(
            code: "DATAFLOW_OPERATION_CONTRACT_INVALID",
            message: "The operation requires \(contract).",
            entity: entity,
            action: "repair_operation_contract"
        )
    }

    private func error(
        code: String,
        message: String,
        entity: String? = nil,
        action: String
    ) -> LogicDiagnostic {
        LogicDiagnostic(
            severity: .error,
            code: code,
            message: message,
            entity: entity,
            suggestedActions: [action]
        )
    }
}
