# LogicDesign Capability and Responsibility Report

## Native capability

The package currently provides a deterministic, in-process subset for:

- stable RTL identities, source spans and SHA-256 source provenance;
- ANSI SystemVerilog modules, ports, parameters, numeric/expression/function-like compiler macros, relative include resolution, constant expressions, vectors and memories;
- hierarchy flattening for connected ports, indexed/part-selected outputs, direct inout nets and parameterized memories, with deterministic instance-path naming and recursion diagnostics;
- instance parameter overrides with declaration-order parameter evaluation, symbolic port/signal range resolution and contextual constant generate expansion;
- conditional compilation and macro expansion using `ifdef`, `ifndef`, `elsif`, `else` and `endif`, including recursive-expansion diagnostics;
- continuous assignments, procedural assignments, `if`, typed `case`/`casex`/`casez`, inferred `always_comb`/`always_latch` sensitivities, module instances and named connections;
- canonical JSON snapshot round trips with schema/digest verification and RTL/gate structural validation;
- gate pin/net reverse-reference, driver/load direction, duplicate identity and connectivity validation;
- UPF/CPF power domains, supply sets, domain supply association, isolation, level shifters, retention and structured source directives;
- typed domain requests and results with failed, blocked and cancelled execution states;
- request contract validation for schema version, run identity, top design and artifact integrity metadata;
- retained reference-oracle correlation for the 13-case SystemVerilog corpus, including source digest binding, canonical snapshot digests and structured mismatch evidence;
- a deterministic JSON CLI (`logic-design`).

## Intentional responsibility boundary

The native frontend is complete for the LogicDesign canonical subset and fails closed for constructs whose semantics are not represented by its public IR. Project-relative include graphs are resolved through the injected source provider; malformed, missing, and cyclic includes produce typed diagnostics. Non-constant generate constructs, unresolved parameter contexts, interfaces/programs/packages/classes, concurrent assertions and full UPF/CPF language semantics are explicit package-boundary limitations, not unfinished LogicDesign tasks. The parser retains typed case/latch semantics in RTL IR so downstream consumers can make their own lowering decision without losing source intent. External-tool correlation and process/foundry qualification are owned by the platform qualification layer.

## Evidence boundary

The 20 fixtures in `Fixtures/manifest.json` are native corpus evidence, while `Fixtures/oracle/manifest.json` is a retained local reference-correlation artifact. The latter verifies deterministic implementation behavior against independently retained expected outputs; it does not establish external-tool agreement, PDK scope, foundry approval or release signoff. Xcircuite and the separate qualification packages remain responsible for their own artifact persistence, policy gates, human approval and resume handling.
