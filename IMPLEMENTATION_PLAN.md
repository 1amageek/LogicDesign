# LogicDesign Implementation Plan

## Order

1. Stable identity and source mapping
2. SystemVerilog parse and elaboration subset
3. Gate-netlist serialization
4. UPF and CPF semantics

## Delivered native implementation slice

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

The declared native subset is complete and smoke-tested. Full-language coverage outside the canonical IR, external-oracle correlation and foundry/process qualification are explicit responsibility boundaries and are never inferred from parser success.
