import Testing
import LogicIR

@Suite("LogicDesign validation")
struct ValidationTests {
    @Test("unresolved RTL references are errors")
    func unresolvedReference() {
        let module = RTLModule(
            id: "m",
            name: "top",
            ports: [RTLPort(id: "p", name: "y", direction: .output)],
            assignments: [RTLAssignment(
                id: "a",
                target: .identifier("y"),
                value: .identifier("missing")
            )]
        )
        let result = LogicDesignValidator().validate(RTLDesign(topModuleName: "top", modules: [module]))
        #expect(!result.isValid)
        #expect(result.diagnostics.contains { $0.code == "LOGIC_REFERENCE_UNRESOLVED" })
    }

    @Test("structural gate netlists build stable cells and nets")
    func gateNetlistParser() {
        let source = "module top(a, y); wire n1; NAND2_X1 u1(.A(a), .B(a), .Y(n1)); INV_X1 u2(.A(n1), .Y(y)); endmodule"
        let result = GateNetlistParser().parse(source, path: "gate.v", topDesignName: "top")
        #expect(result.isValid)
        #expect(result.design?.modules.first?.cells.count == 2)
        #expect(result.design?.modules.first?.nets.contains { $0.name == "n1" } == true)
    }

    @Test("gate validation rejects a stale net pin index")
    func staleGateNetPinReferenceIsRejected() {
        let pin = GatePin(id: "pin-1", name: "Y", direction: .output, netID: "net-1")
        let cell = GateCell(id: "cell-1", type: "INV_X1", instanceName: "u1", pins: [pin])
        let net = GateNet(id: "net-1", name: "n1", driverPinIDs: ["missing-pin"])
        let module = GateModule(id: "module-1", name: "top", cells: [cell], nets: [net])
        let result = LogicDesignValidator().validate(GateDesign(topModuleName: "top", modules: [module]))
        #expect(result.isValid == false)
        #expect(result.diagnostics.contains { $0.code == "GATE_NET_PIN_UNRESOLVED" })
    }
}
