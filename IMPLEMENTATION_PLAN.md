# LogicDesign Implementation Plan

## Order

1. Stable identity and source mapping
2. SystemVerilog parse and elaboration subset
3. Gate-netlist serialization
4. UPF and CPF semantics

## Legacy host implementation slice

- Stable RTL/gate identity, source spans, source SHA-256 provenance and canonical snapshot codec.
- SystemVerilog lexer/parser for ANSI modules, parameters, numeric/expression/function-like macros, constant expressions, vectors, memories, assignments, procedural control, hierarchy and constant generate elaboration.
- Structural gate netlist parser for mapped cells, pins and nets.
- UPF/CPF parser and validator for domains, supply sets, isolation, level shifting, retention and structured source directives.
- Deterministic CLI, positive/negative fixtures, structured blocked diagnostics and JSON round-trip tests.

## Completion gates

- Public APIs remain protocol-first and Sendable.
- Every unsupported semantic produces a structured blocked result.
- Native and external backends produce the same result schema.
- No UI type enters a public contract.
- No result claims foundry qualification without process-scoped oracle evidence.
- Downstream flow runtimes can execute, persist, review and resume stages through the published contracts.

## Qualification boundary

Legacy host fixtures establish only their exercised draft-IR paths. Portable
elaboration, width/sign/process semantics, actual-cell simulation, symbolic proof
and state-preserving optimization each require evidence for their own contracts.
The normative portable contracts belong to
[SystemVerilogFrontend](Sources/SystemVerilogFrontend/DESIGN.md) and
[LogicIR](Sources/LogicIR/DESIGN.md); current work and completion evidence belong
only to [PROGRESS.md](../PROGRESS.md). Component tests do not imply full-language,
foundry or tool qualification.
