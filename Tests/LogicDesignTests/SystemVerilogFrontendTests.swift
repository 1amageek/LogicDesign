import Foundation
import Testing
import LogicIR
import SystemVerilogFrontend

@Suite("SystemVerilog frontend")
struct SystemVerilogFrontendTests {
    @Test("lexing preserves source locations")
    func lexingPreservesLocations() {
        let source = SystemVerilogSourceUnit(path: "fixture.sv", source: "module top;\nendmodule")
        let result = SystemVerilogLexer().lex(source)
        #expect(result.diagnostics.isEmpty)
        #expect(result.tokens.first?.lexeme == "module")
        #expect(result.tokens.first?.span.start.line == 1)
        #expect(result.tokens.dropFirst().first?.span.start.line == 1)
    }

    @Test("numeric compiler macros are evaluated without losing source provenance")
    func parsesNumericCompilerMacro() {
        let source = SystemVerilogSourceUnit(
            path: "macro.sv",
            source: """
            `timescale 1ns/1ps
            `define WIDTH 4
            module top(input logic [`WIDTH-1:0] a, output logic [`WIDTH-1:0] y);
                assign y = a;
            endmodule
            """
        )
        let result = SystemVerilogParser().parse([source], topDesignName: "top")
        #expect(result.diagnostics.isEmpty)
        #expect(result.design?.sourceFiles.first?.path == "macro.sv")
        #expect(result.design?.modules.first?.ports.first?.range?.width == 4)
    }

    @Test("conditional compilation selects the active macro branch")
    func selectsConditionalCompilationBranch() {
        let source = SystemVerilogSourceUnit(
            path: "conditional-compilation.sv",
            source: """
            `define SECOND 1
            `ifdef FIRST
                module top(input logic a, output logic y);
                    assign y = 1'b0;
                endmodule
            `elsif SECOND
                module top(input logic a, output logic y);
                    assign y = a;
                endmodule
            `else
                module top(input logic a, output logic y);
                    assign y = 1'b1;
                endmodule
            `endif
            """
        )
        let result = SystemVerilogParser().parse([source], topDesignName: "top")

        #expect(result.unsupportedSemantics == false)
        #expect(result.diagnostics.isEmpty)
        #expect(result.design?.modules.count == 1)
        #expect(result.design?.modules.first?.assignments.count == 1)
        if case .identifier(let name) = result.design?.modules.first?.assignments.first?.value {
            #expect(name == "a")
        } else {
            Issue.record("Expected the active conditional branch assignment")
        }
    }

    @Test("unterminated conditional compilation is blocked with a typed diagnostic")
    func blocksUnterminatedConditionalCompilation() {
        let source = SystemVerilogSourceUnit(
            path: "unterminated-conditional.sv",
            source: """
            `ifdef ENABLED
            module top(input logic a, output logic y);
                assign y = a;
            endmodule
            """
        )
        let result = SystemVerilogParser().parse([source], topDesignName: "top")

        #expect(result.unsupportedSemantics)
        #expect(result.diagnostics.contains {
            $0.code == "SV_CONDITIONAL_UNTERMINATED"
        })
    }

    @Test("unsupported include directives remain blocked")
    func blocksUnsupportedIncludeDirective() {
        let source = SystemVerilogSourceUnit(
            path: "include.sv",
            source: "`include \"defs.svh\"\nmodule top; endmodule"
        )
        let result = SystemVerilogParser().parse([source], topDesignName: "top")
        #expect(result.unsupportedSemantics)
        #expect(result.diagnostics.contains { $0.code == "SV_UNSUPPORTED_DIRECTIVE" })
    }

    @Test("parsing builds canonical RTL for parameterized ANSI modules")
    func parsesParameterizedModule() {
        let source = SystemVerilogSourceUnit(
            path: "counter.sv",
            source: """
            module counter #(parameter WIDTH = 8) (
                input logic clk,
                input logic [WIDTH-1:0] d,
                output logic [WIDTH-1:0] q
            );
                always_ff @(posedge clk) begin
                    q <= d;
                end
            endmodule
            """
        )
        let result = SystemVerilogParser().parse([source], topDesignName: "counter")
        #expect(result.diagnostics.isEmpty)
        #expect(result.design?.topModuleName == "counter")
        #expect(result.design?.modules.count == 1)
        #expect(result.design?.modules.first?.parameters.first?.value == 8)
        #expect(result.design?.modules.first?.ports.first(where: { $0.name == "q" })?.range?.width == 8)
        #expect(result.design?.modules.first?.processes.count == 1)
        #expect(result.design?.modules.first?.processes.first?.clockEdge == .positive)
    }

    @Test("retains parameter, range, and generate expressions for contextual elaboration")
    func retainsContextualElaborationExpressions() {
        let source = SystemVerilogSourceUnit(
            path: "context.sv",
            source: """
            module context #(parameter BASE = 1, parameter WIDTH = BASE + 1, parameter COUNT = 2) (
                input logic [WIDTH-1:0] a,
                output logic [WIDTH-1:0] y
            );
                wire [COUNT-1:0] bits;
                generate
                    for (genvar i = 0; i < COUNT; i = i + 1) begin : g
                        assign bits[i] = a[0];
                    end
                endgenerate
                assign y = a;
            endmodule
            """
        )
        let result = SystemVerilogParser().parse([source], topDesignName: "context")
        let module = result.design?.modules.first

        #expect(result.diagnostics.isEmpty)
        #expect(module?.parameters.first(where: { $0.name == "WIDTH" })?.defaultExpression != nil)
        #expect(module?.ports.first(where: { $0.name == "a" })?.rangeExpression != nil)
        #expect(module?.signals.first?.rangeExpression != nil)
        #expect(module?.generateBlocks.first?.startExpression != nil)
        #expect(module?.generateBlocks.first?.limitExpression != nil)
        #expect(module?.generateBlocks.first?.stepExpression != nil)
    }

    @Test("retains a negative clock edge in the canonical RTL process")
    func retainsNegativeClockEdge() {
        let source = SystemVerilogSourceUnit(
            path: "negative-edge.sv",
            source: "module top(input logic clk, input logic d, output logic q); always_ff @(negedge clk) q <= d; endmodule"
        )
        let result = SystemVerilogParser().parse([source], topDesignName: "top")
        #expect(result.diagnostics.isEmpty)
        #expect(result.design?.modules.first?.processes.first?.clockEdge == .negative)
    }

    @Test("case statements and latch processes are retained")
    func parsesCaseAndLatch() {
        let source = SystemVerilogSourceUnit(
            path: "case.sv",
            source: """
            module top(input logic enable, input logic select, input logic a, output logic y);
                always_latch begin
                    if (enable) begin
                        case (select)
                            1'b0: y = a;
                            default: y = 1'b0;
                        endcase
                    end
                end
            endmodule
            """
        )
        let result = SystemVerilogParser().parse([source], topDesignName: "top")
        #expect(result.diagnostics.isEmpty)
        #expect(result.design?.modules.first?.processes.first?.kind == .latch)
        guard let statement = result.design?.modules.first?.processes.first?.statements.first else {
            Issue.record("Expected a latch statement")
            return
        }
        guard case .block(let statements) = statement,
              case .conditional(_, let ifTrue, _) = statements.first,
              case .typedCaseStatement(let kind, _, let items, let defaults) = ifTrue.first else {
                Issue.record("Expected a case statement in the latch body")
                return
        }
        #expect(kind == .standard)
        #expect(items.count == 1)
        #expect(defaults.count == 1)
    }

    @Test("hierarchy and named connections are retained")
    func parsesHierarchy() {
        let source = SystemVerilogSourceUnit(
            path: "hierarchy.sv",
            source: """
            module leaf(input logic a, output logic y);
                assign y = a;
            endmodule
            module top(input logic a, output logic y);
                leaf u_leaf(.a(a), .y(y));
            endmodule
            """
        )
        let result = SystemVerilogParser().parse([source], topDesignName: "top")
        #expect(result.diagnostics.isEmpty)
        #expect(result.design?.modules.last?.instances.first?.moduleName == "leaf")
        #expect(result.design?.modules.last?.instances.first?.connections.count == 2)
    }

    @Test("unsupported semantics are explicit")
    func blocksGenerate() {
        let source = SystemVerilogSourceUnit(
            path: "unsupported.sv",
            source: "module top(input logic a, output logic y); generate if (a) begin : g assign y = a; end endgenerate endmodule"
        )
        let result = SystemVerilogParser().parse([source], topDesignName: "top")
        #expect(result.unsupportedSemantics)
        #expect(result.diagnostics.contains { $0.code == "SV_UNSUPPORTED_GENERATE" })
    }

    @Test("constant generate-for blocks are retained for elaboration")
    func parsesGenerateFor() {
        let source = SystemVerilogSourceUnit(
            path: "generated.sv",
            source: """
            module top(input logic a, output logic y);
                generate
                    for (genvar i = 0; i < 2; i = i + 1) begin : g
                        assign y = a;
                    end
                endgenerate
            endmodule
            """
        )
        let result = SystemVerilogParser().parse([source], topDesignName: "top")
        #expect(result.diagnostics.isEmpty)
        #expect(result.design?.modules.first?.generateBlocks.count == 1)
        #expect(result.design?.modules.first?.generateBlocks.first?.limit == 2)
    }

    @Test("constant generate-if selects one branch during elaboration")
    func parsesGenerateIf() {
        let source = SystemVerilogSourceUnit(
            path: "conditional.sv",
            source: """
            module top(input logic a, output logic y);
                parameter ENABLE = 1;
                generate
                    if (ENABLE) begin : enabled
                        assign y = a;
                    end else begin : disabled
                        assign y = 1'b0;
                    end
                endgenerate
            endmodule
            """
        )
        let result = SystemVerilogParser().parse([source], topDesignName: "top")
        #expect(result.unsupportedSemantics == false)
        #expect(result.design?.modules.first?.generateBlocks.count == 2)
        if let design = result.design {
            let elaborated = RTLGenerateElaborator().elaborate(design)
            #expect(elaborated.modules.first?.generateBlocks.isEmpty == true)
            #expect(elaborated.modules.first?.assignments.count == 1)
        }
    }
}
