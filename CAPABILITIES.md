# LogicDesign Capability and Limitation Report

## Native capability

The package currently provides a deterministic, in-process subset for:

- stable RTL identities, source spans and SHA-256 source provenance;
- ANSI SystemVerilog modules, ports, parameters, numeric object-like compiler macros, relative include resolution, constant expressions, vectors and memories;
- hierarchy flattening for connected identifier-based ports, with deterministic instance-path naming and recursion diagnostics;
- instance parameter overrides with declaration-order parameter evaluation, symbolic port/signal range resolution and contextual constant generate expansion;
- conditional compilation for numeric object-like macros using `ifdef`, `ifndef`, `elsif`, `else` and `endif`;
- continuous assignments, supported procedural assignments, `if`, and canonical retention of `case`/`always_latch` statements, module instances and named connections;
- canonical JSON snapshot round trips with schema/digest verification and RTL/gate structural validation;
- gate pin/net reverse-reference, driver/load direction, duplicate identity and connectivity validation;
- UPF/CPF power domains, supply sets, domain supply association, isolation, level shifters, retention and retained directives;
- typed request/result envelopes with failed, blocked and cancelled execution states;
- request contract validation for schema version, run identity, top design and artifact integrity metadata;
- a deterministic JSON CLI (`logic-design`).

## Explicit limitations

The native frontend blocks unsupported semantics rather than treating them as verified. The elaborating engine resolves project-relative include graphs through the injected source provider and reports malformed, missing, and cyclic includes as typed diagnostics. Direct parsing without include resolution, function-like or expression-valued preprocessor directives, non-constant or else-if generate constructs, interfaces, packages, classes, assertions, full UPF/CPF semantics and external-tool correlation remain blocked. Constant generate-if/else, parameterized generate-for, numeric macros, object-like conditional compilation, symbolic ranges and identifier-connected hierarchy are supported by native elaboration. Unresolved parameter contexts, bidirectional ports and non-identifier output connections remain blocked with typed diagnostics. Case statements and latch processes are parsed and retained in RTL IR; lowerers that cannot preserve their semantics must return a structured blocked result. No process-specific foundry qualification is claimed.

## Evidence boundary

The fixtures in `Fixtures/` and the contract/parser tests are smoke corpus evidence only. Xcircuite remains responsible for resolving project-relative artifact references, verifying digests, persisting returned artifacts, applying qualification policy, human approval and resume handling.
