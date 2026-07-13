# LogicDesign Goal Status

## Current state

**LogicDesign package-local implementation is complete. Platform-level qualification and orchestration remain outside this package and are not LogicDesign tasks.**

| Maturity gate | Status | Evidence |
|---|---|---|
| Responsibility boundary | Complete | README.md and DESIGN.md |
| Public package products | Implemented | Package.swift |
| Shared Xcircuite request/result contract | Implemented | Public Swift protocols and payloads |
| Contract build | Passed | swift build |
| Contract test | Passed | timeout-bounded `xcodebuild test`; 52 tests in 5 suites |
| Domain implementation | Complete for native subset | LogicIR, SystemVerilogFrontend, PowerIntent and gate netlist parser |
| CLI implementation | Complete | `logic-design` parse, validate, correlate, gate-parse, power-intent and capabilities |
| Fixture corpus | Complete for native corpus | `Fixtures/manifest.json` records 20 retained cases with SHA-256 and expected native status, including macro expansion, generate branching, indexed/inout hierarchy, parameterized memory, power directives, sensitivity events and typed blocked cases |
| Oracle correlation | Complete for retained local reference corpus | `Fixtures/oracle/manifest.json` correlates 17 SystemVerilog cases by source SHA-256, status, completed snapshot digest and typed negative diagnostic codes; this is not external-tool qualification |
| Process qualification | External responsibility | PDK/process qualification is owned by the separate qualification workflow |
| Xcircuite stage adapter | External responsibility | Xcircuite owns runtime adapters, persistence, trust gates and approval/resume orchestration |
| End-to-end flow evidence | External responsibility | Downstream packages own simulation, timing, physical, PEX and human review flow evidence |
| Release readiness | External responsibility | Release policy consumes LogicDesign artifacts but is not implemented by this package |

## Active milestones

The detailed roadmap and exit criteria are maintained in `MILESTONES.md`.

| Milestone | Status | Current exit gap |
|---|---|---|
| 0. Requirements and evidence baseline | Complete | Baseline and responsibility boundaries recorded |
| 1. Canonical contract and artifact integrity | Complete for LogicDesign | Snapshot/request validation, deterministic canonical-vs-serialized digests and typed execution evidence are implemented |
| 2. Deterministic HDL and power-intent semantics | Complete for declared native subset | Macro expansion, include resolution, constant generate, procedural IR, symbolic ranges, parameterized hierarchy, connected hierarchy, structured power directives and typed diagnostics are implemented |
| 3. Cross-engine design identity | Complete for LogicDesign contracts | Canonical-vs-serialized digest separation, gate connectivity validation and `LogicDesignProvenance` are implemented and round-trip tested |
| 4. Xcircuite execution and human-in-the-loop | External responsibility | Xcircuite consumes LogicDesign contracts and owns runtime execution, persistence, review and resume |
| 5. Qualification and release eligibility | External responsibility | Qualification and release packages consume LogicDesign evidence and own tool/process policy |

## Function status

| Function | Contract | Implementation | Validation corpus | Qualification |
|---|---|---|---|---|
| SystemVerilog lexical and syntax frontend | Contract defined | Native subset implemented | Positive/negative fixtures | Smoke checked |
| Preprocessing and elaboration | Contract defined | Numeric, expression-valued and function-like macros, object-like conditional compilation, declaration-order parameters, relative include graphs, constant expressions, inclusive/descending generate-for, constant generate-if/else-if/else, symbolic ranges and connected hierarchy flattening | Positive preprocessing/include/hierarchy/generate/conditional fixtures plus typed include, recursive-hierarchy, unresolved-parameter and unterminated-conditional failures | Complete for native subset |
| RTL IR | Contract defined | Processes, inferred sensitivities, expressions, typed case/latch statements, source-ordered clock/reset event metadata, registers, memories, ports and connectivity | Parser, hierarchy and snapshot tests | Complete for native subset |
| Gate-design IR | Contract defined | Structural cell/pin/net parser, reverse connectivity and validator | Gate parser and negative connectivity tests | Smoke checked |
| Round-trip serialization | Contract defined | Canonical JSON snapshot codec with schema/digest verification | Round-trip and tamper tests | Smoke checked |
| UPF and CPF parsing | Contract defined | Native policy subset with structured directive retention | UPF/CPF fixtures and design round-trip tests | Complete for native subset |
| Design validation | Contract defined | Structured unresolved-reference/connectivity checks | Negative tests | Smoke checked |

## Goal progression

```text
contract scaffold
      ↓
narrow implementation
      ↓
negative-path fixtures
      ↓
corpus validation
      ↓
reference-oracle correlation
      ↓
process-scoped qualification
      ↓
Xcircuite integration and repair loop
      ↓
release-profile eligibility
```

## Completion definition

The LogicDesign package goal is complete when every LogicDesign-owned P0 function has a concrete backend, structured failure behavior, retained corpus, reference correlation where an oracle exists, a deterministic CLI and passing package tests. Process qualification, Xcircuite execution and release approval are explicit consumer responsibilities.

## External prerequisites

- Full SystemVerilog, UPF and CPF language semantics outside the declared native IR are intentional package-boundary limitations and return typed blocked diagnostics.
- External-tool correlation, process-specific corpus qualification, production PEX execution and release approval are owned by separate packages.
- LogicDesign's retained reference oracle correlation passes for 17 SystemVerilog cases; parallel shared-workspace runs are not signoff evidence.
- The LogicEngine lowering slice consumes the canonical `LogicDesignReference.designDigest` for RTL snapshots while retaining `artifact.sha256` for serialized-byte integrity.

This file must be updated by implementation agents whenever a maturity gate changes. A source file or type name alone is never evidence of implementation or qualification.
