# LogicDesign Implementation Plan

## Order

1. Stable identity and source mapping
2. SystemVerilog parse and elaboration subset
3. Gate-netlist serialization
4. UPF and CPF semantics

## Delivered native implementation slice

- Stable RTL/gate identity, source spans, source SHA-256 provenance and canonical snapshot codec.
- SystemVerilog lexer/parser for ANSI modules, parameters, constant expressions, vectors, memories, assignments, supported procedural control, hierarchy and constant generate-for elaboration.
- Structural gate netlist parser for mapped cells, pins and nets.
- UPF/CPF parser and validator for domains, supply sets, isolation, level shifting, retention and retained directives.
- Deterministic CLI, positive/negative fixtures, structured blocked diagnostics and JSON round-trip tests.
- Xcircuite-side headless stage executors for elaboration and power intent.

## Completion gates

- Public APIs remain protocol-first and Sendable.
- Every unsupported semantic produces a structured blocked result.
- Native and external backends produce the same result schema.
- No UI type enters a public contract.
- No result claims foundry qualification without process-scoped oracle evidence.
- Xcircuite can execute, persist, review and resume the stage without circuit-studio.

## Qualification boundary

The native subset is smoke-checked only. Full-language coverage, external-oracle correlation and foundry/process qualification remain separate gates and are represented as blocked capability evidence rather than inferred from parser success.
