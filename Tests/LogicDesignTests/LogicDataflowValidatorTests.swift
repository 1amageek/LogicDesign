import LogicIR
import Testing

@Suite("Canonical dataflow validation")
struct LogicDataflowValidatorTests {
    @Test("arbitrary-width bit vectors retain their complete value")
    func arbitraryWidthBitVector() throws {
        let value = try LogicBitVector(
            width: 128,
            literalText: "0xffffffffffffffffffffffffffffffff"
        )

        #expect(value.bytes == [UInt8](repeating: 0xff, count: 16))
        #expect(try LogicBitVector(width: 8, literalText: "-128").bytes == [0x80])
        #expect(try LogicBitVector(width: 8, literalText: "-1").bytes == [0xff])
        #expect(throws: LogicBitVectorError.self) {
            _ = try LogicBitVector(width: 8, literalText: "-129")
        }
        #expect(throws: LogicBitVectorError.self) {
            _ = try LogicBitVector(width: 127, bytes: value.bytes)
        }
    }

    @Test("function graphs validate ordered SSA references and return types")
    func validFunctionGraph() throws {
        let one = try LogicBitVector(width: 32, literalText: "1")
        let design = LogicDataflowDesign(
            packageName: "arithmetic",
            topEntityName: "add_one",
            functions: [
                LogicDataflowFunction(
                    name: "add_one",
                    parameters: [LogicDataflowParameter(name: "input", type: .bits(width: 32))],
                    returnType: .bits(width: 32),
                    nodes: [
                        LogicDataflowNode(
                            name: "one.1",
                            type: .bits(width: 32),
                            operation: LogicDataflowOperation(
                                kind: .literal,
                                attributes: [
                                    LogicDataflowAttribute(name: "value", value: .literal(.bits(one))),
                                ]
                            ),
                            externalNumericID: 1
                        ),
                        LogicDataflowNode(
                            name: "sum.2",
                            type: .bits(width: 32),
                            operation: LogicDataflowOperation(
                                kind: .add,
                                operands: ["input", "one.1"]
                            ),
                            externalNumericID: 2
                        ),
                    ],
                    returnValue: "sum.2"
                ),
            ]
        )

        let result = LogicDataflowValidator().validate(design)

        #expect(result.isValid)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("stateful process graphs require explicit type-correct next-state semantics")
    func statefulProcessContract() throws {
        let zero = try LogicBitVector(width: 32, literalText: "0")
        let design = LogicDataflowDesign(
            packageName: "stateful",
            topEntityName: "counter",
            processes: [
                LogicDataflowProcess(
                    name: "counter",
                    stateElements: [
                        LogicDataflowStateElement(
                            name: "count",
                            type: .bits(width: 32),
                            initialValue: .bits(zero)
                        ),
                    ],
                    nodes: [
                        LogicDataflowNode(
                            name: "read.1",
                            type: .bits(width: 32),
                            operation: LogicDataflowOperation(
                                kind: .stateRead,
                                attributes: [
                                    LogicDataflowAttribute(
                                        name: "state_element",
                                        value: .identifier("count")
                                    ),
                                ]
                            )
                        ),
                    ],
                    nextStateValues: ["missing"]
                ),
            ]
        )

        let result = LogicDataflowValidator().validate(design)

        #expect(!result.isValid)
        #expect(result.diagnostics.contains { $0.code == "DATAFLOW_NEXT_STATE_UNRESOLVED" })
    }

    @Test("extended arithmetic and bit operations retain canonical type semantics")
    func extendedOperationContracts() {
        let design = LogicDataflowDesign(
            packageName: "bit_operations",
            topEntityName: "transform",
            functions: [
                LogicDataflowFunction(
                    name: "transform",
                    parameters: [
                        LogicDataflowParameter(name: "input", type: .bits(width: 8)),
                        LogicDataflowParameter(name: "mask", type: .bits(width: 8)),
                        LogicDataflowParameter(name: "amount", type: .bits(width: 3)),
                    ],
                    returnType: .bits(width: 1),
                    nodes: [
                        LogicDataflowNode(
                            name: "combined.1",
                            type: .bits(width: 8),
                            operation: LogicDataflowOperation(
                                kind: .bitwiseNand,
                                operands: ["input", "mask", "input"]
                            )
                        ),
                        LogicDataflowNode(
                            name: "shifted.2",
                            type: .bits(width: 8),
                            operation: LogicDataflowOperation(
                                kind: .shiftLeftLogical,
                                operands: ["combined.1", "amount"]
                            )
                        ),
                        LogicDataflowNode(
                            name: "reversed.3",
                            type: .bits(width: 8),
                            operation: LogicDataflowOperation(
                                kind: .reverseBits,
                                operands: ["shifted.2"]
                            )
                        ),
                        LogicDataflowNode(
                            name: "compared.4",
                            type: .bits(width: 1),
                            operation: LogicDataflowOperation(
                                kind: .unsignedLessThan,
                                operands: ["reversed.3", "input"]
                            )
                        ),
                    ],
                    returnValue: "compared.4"
                ),
            ]
        )

        let result = LogicDataflowValidator().validate(design)

        #expect(result.isValid)
        #expect(LogicDataflowOperationKind.subtract.rawValue == "subtract")
        #expect(LogicDataflowOperationKind.unsignedLessThan.rawValue == "unsignedLessThan")
    }

    @Test("numeric comparisons reject aggregate operands")
    func numericComparisonRejectsAggregateOperands() {
        let tupleType = LogicDataflowType.tuple([.bits(width: 8)])
        let design = LogicDataflowDesign(
            packageName: "invalid_compare",
            topEntityName: "compare",
            functions: [
                LogicDataflowFunction(
                    name: "compare",
                    parameters: [
                        LogicDataflowParameter(name: "left", type: tupleType),
                        LogicDataflowParameter(name: "right", type: tupleType),
                    ],
                    returnType: .bits(width: 1),
                    nodes: [
                        LogicDataflowNode(
                            name: "result.1",
                            type: .bits(width: 1),
                            operation: LogicDataflowOperation(
                                kind: .signedLessThan,
                                operands: ["left", "right"]
                            )
                        ),
                    ],
                    returnValue: "result.1"
                ),
            ]
        )

        let result = LogicDataflowValidator().validate(design)

        #expect(!result.isValid)
        #expect(result.diagnostics.contains { $0.code == "DATAFLOW_OPERATION_CONTRACT_INVALID" })
    }
}
