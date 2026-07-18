# LogicDesign

Canonical digital design state, SystemVerilog frontend and power-intent contracts for a local semiconductor design platform.

## Status

This package provides the complete LogicDesign-owned native implementation for canonical RTL and power-intent state. It is designed for both human workflows and structured Agent workflows through typed Swift APIs, immutable artifacts and a deterministic JSON CLI.

The implementation is explicit about its validation and evidence boundary: unsupported language semantics return structured blocked results, while native parser success produces evidence for an independent qualification decision rather than owning that decision.

## Products

| Product | Responsibility |
|---|---|
| `LogicIR` | Stable RTL/gate identity, source provenance, snapshots and validation |
| `SystemVerilogFrontend` | Lexing, parsing, parameter evaluation, relative include resolution and canonical RTL elaboration subset |
| `PowerIntent` | UPF/CPF domain and low-power policy parsing/validation subset |
| `LogicDesign` | Umbrella API |
| `logic-design` | Deterministic JSON CLI for parse, validate, gate-parse, power-intent, reference correlation and capability inspection |

## Design flow

```mermaid
flowchart LR
  Source["SV / UPF / CPF sources"] --> Frontend["Frontend and typed diagnostics"]
  Frontend --> Snapshot["Canonical LogicDesignSnapshot"]
  Snapshot --> Artifact["Immutable artifact reference"]
  Artifact --> Consumers["Simulation / synthesis / verification / DFT / timing / physical design"]
  Consumers --> Evidence["Structured results and review artifacts"]
```

Reference correlation is a separate, digest-bound evidence path:

```mermaid
flowchart LR
  Source["SystemVerilog fixture"] --> Native["Native elaboration"]
  Source --> Digest["Input SHA-256"]
  Oracle["Retained oracle manifest"] --> Correlator["LogicDesignOracleCorrelator"]
  Native --> Correlator
  Digest --> Correlator
  Correlator --> Evidence["Matched / mismatched JSON evidence"]
```

## Native capability

- Stable RTL and gate identities, source locations and source-file SHA-256 provenance.
- Canonical JSON snapshots with schema validation, deterministic digesting and tamper detection.
- Transformation-aware `LogicDesignReference` lineage preserves the original canonical digest, immediate input digest, transformation ID, producer version and run ID across engine handoffs.
- ANSI SystemVerilog modules, parameters, numeric/expression/function-like macros, constant expressions, vectors, memories, assignments, supported processes and hierarchy.
- Instance parameter overrides are resolved per hierarchy context, including symbolic port/signal ranges and constant generate bounds.
- Clocked process event lists preserve source order and per-signal edge metadata, including asynchronous reset events, through hierarchy elaboration; `always_comb` and `always_latch` infer deterministic read sensitivities.
- Object-like, expression-valued and function-like macro expansion supports `ifdef`, `ifndef`, `elsif`, `else` and `endif`; recursive expansion and malformed invocations return typed diagnostics.
- Project-relative `` `include `` graph resolution through an injected source provider. Malformed, missing and cyclic includes produce typed diagnostics.
- Constant `generate-for` (including inclusive bounds and descending steps) and mutually exclusive `generate-if/else-if/else` elaboration, structural gate netlist parsing and connectivity validation.
- UPF/CPF domain, supply-set, isolation, level-shifter and retention policy modeling with structured directive retention and source provenance.
- Hierarchy flattening for indexed/part-selected output connections, direct inout nets and parameterized memories.
- Retained positive and negative fixtures in `Fixtures/manifest.json`, including SHA-256 integrity and expected native status.
- A retained SystemVerilog reference corpus in `Fixtures/oracle/manifest.json`; its 17 cases bind source SHA-256, expected status, completed snapshot digests and negative diagnostic codes.
- Typed `LogicDesignOracleManifest`, `LogicDesignOracleCorrelator` and `LogicDesignOracleCorrelation` APIs for Agent/CI-readable comparison evidence. Correlation accepts only the exact canonical case stored in the validated manifest and retains deterministic manifest and case digests.

## Contract

Every executing product uses:

- a `Codable`, `Hashable`, `Sendable` request with `ArtifactLocator` inputs;
- domain-owned result types (`LogicElaborationResult` and `PowerIntentParsingResult`) for status, diagnostics and execution metadata;
- domain protocols that refine `CircuiteFoundation.Engine` directly;
- direct `ArtifactProducing`, `DiagnosticReporting` and `EvidenceProviding`
  conformance on execution results;
- protocol-first dependency injection;
- `ArtifactLocator` for planned inputs and `ArtifactReference` for materialized outputs;
- explicit blocked, failed and cancelled states.

## Xcircuite integration

Xcircuite treats `LogicDesignReference` and `PowerIntentReference` as canonical stage handoffs consumed by simulation, synthesis, verification, DFT, timing and physical design. The LogicDesign frontend resolves project-root-relative source includes and persists canonical snapshots; run lifecycle and artifact integrity gates are owned by the integrating flow runtime.

The library does not depend on the Xcircuite runtime. Xcircuite owns `DesignFlowKernel` integration, artifact persistence, qualification gates, repair loops and human approval.

## CLI

The CLI emits deterministic JSON for machine consumption. A successful operation exits with status `0`; invalid input, failed validation or blocked native semantics exits non-zero and includes structured diagnostics.

The `capabilities` command emits capability report schema version 2. The report declares supported capabilities, blocked language semantics, package-owned validation checks and a typed evidence boundary. `LogicDesignEvidenceBoundary.producedEvidence` lists evidence produced by this package, while `externalDecisions` lists decisions owned by ToolQualification, process policy and release authorization. It does not contain a package-owned qualification result.

```bash
swift run logic-design capabilities
swift run logic-design parse --input Fixtures/positive/simple_counter.sv --top counter --output /tmp/counter.json
swift run logic-design correlate --input Fixtures/positive/simple_counter.sv --oracle Fixtures/oracle/manifest.json --case simple-counter
swift run logic-design gate-parse --input Fixtures/positive/simple_gate.v --top top
swift run logic-design power-intent --input Fixtures/power/sample.cpf --format cpf --top top --design <design.json>
```

## Build and test

```bash
swift build
perl -e 'alarm 30; exec @ARGV' xcodebuild test -scheme LogicDesign-Package -destination 'platform=macOS'
```

The LogicDesign contract suite passes with 58 package-local tests in 6 suites. The retained fixture corpus contains 20 native cases, and the separate reference manifest correlates all 17 SystemVerilog cases, including completed snapshot digests and typed negative diagnostics. This evidence is local reference correlation, not external-tool or process qualification. Parallel shared-workspace runs are not signoff evidence.

## Evidence and qualification ownership

The LogicDesign-owned native implementation is deterministic and complete for its declared canonical subset. Hierarchy flattening covers connected ports, indexed/part-selected outputs, direct inout nets, parameterized memories, instance parameter overrides, symbolic ranges and contextual constant generate expansion; invalid or genuinely compile-time-unresolvable constructs return typed diagnostics. The retained reference oracle is correlated through a digest-bound typed API and CLI. Full-language external-tool correlation, PDK/process qualification, release approval and human approval/resume orchestration are platform-level responsibilities outside this package. See `CAPABILITIES.md`, `MILESTONES.md` and `GOAL_STATUS.md` for the package boundary and evidence.

See `DESIGN.md`, `INTERFACES.md` and `IMPLEMENTATION_PLAN.md` before implementing a backend.

See `CAPABILITIES.md` for the validation/evidence boundary and explicit blocked semantics.

## Current integration evidence

The retained LogicDesign reference correlation is available to Xcircuite/Agent callers as structured JSON input evidence. Xcircuite's independent external-oracle execution contract is separately focused-tested, while real external-tool correlation, PDK/process qualification and release-profile eligibility remain explicit gates.
