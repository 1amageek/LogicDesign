# LogicDesign Goal Status

## Current state

**Milestone-based implementation in progress. The initial native slice is smoke-checked; the broader platform goal remains open.**

| Maturity gate | Status | Evidence |
|---|---|---|
| Responsibility boundary | Complete | README.md and DESIGN.md |
| Public package products | Implemented | Package.swift |
| Shared Xcircuite request/result contract | Implemented | Public Swift protocols and payloads |
| Contract build | Passed | swift build |
| Contract test | Passed | timeout-bounded `swift test`; 36 tests in 5 suites |
| Domain implementation | Complete for native subset | LogicIR, SystemVerilogFrontend, PowerIntent and gate netlist parser |
| CLI implementation | Complete | `logic-design` parse, validate, gate-parse, power-intent and capabilities |
| Fixture corpus | Complete for smoke corpus | `Fixtures/manifest.json` records 8 retained cases with SHA-256 and expected native status |
| Oracle correlation | Not started | No retained comparison evidence |
| Process qualification | Not started | No PDK-scoped qualification record |
| Xcircuite stage adapter | Implemented for LogicDesign and verified focused slices | `LogicElaborationFlowStageExecutor` resolves project-root relative includes, while elaboration/power-intent persist canonical artifacts, envelopes and integrity gates; full shared-worktree regression requires revalidation |
| End-to-end flow evidence | Focused evidence retained; current full rerun pending | The retained multi-engine test defines the canonical RTL → simulation → STA → physical review/resume path; the current fixture path is corrected, but a fresh Xcircuite binary has not been accepted as evidence while concurrent dependency builds are active |
| Release readiness | Blocked | Native subset is smoke-checked; oracle/process qualification and dependent platform test build remain |

## Active milestones

The detailed roadmap and exit criteria are maintained in `MILESTONES.md`.

| Milestone | Status | Current exit gap |
|---|---|---|
| 0. Requirements and evidence baseline | Complete | Baseline and responsibility boundaries recorded |
| 1. Canonical contract and artifact integrity | In progress | Snapshot/request validation and adapter integrity gates are implemented; orchestrated handoff evidence remains |
| 2. Deterministic HDL and power-intent semantics | In progress | Numeric macro/timescale preprocessing, relative include graph resolution, constant generate-if/else, connected hierarchy flattening, case and latch retention are implemented; parameterized hierarchy, conditional compilation and wider procedural coverage remain |
| 3. Cross-engine design identity | In progress | Canonical-vs-serialized digest boundary, gate connectivity validation and shared `LogicDesignProvenance` contract are implemented; producer adoption is covered for LogicEngine, DFT and Xcircuite, while TimingEngine, PhysicalDesignEngine and ReleaseEngine enforce invalid or mismatched lineage; remaining handoff consumers and full signoff-chain evidence remain |
| 4. Xcircuite execution and human-in-the-loop | In progress | Focused stage adapters and the retained flow contract exist; current full dependency-graph rerun remains pending; production PEX, external oracle and complete platform signoff remain |
| 5. Qualification and release eligibility | In progress for gate implementation | Local corpus/oracle and process-scope gates are typed and fail closed, but no retained independent LogicDesign oracle correlation or PDK/foundry process qualification is claimed |

## Function status

| Function | Contract | Implementation | Validation corpus | Qualification |
|---|---|---|---|---|
| SystemVerilog lexical and syntax frontend | Contract defined | Native subset implemented | Positive/negative fixtures | Smoke checked |
| Preprocessing and elaboration | Contract defined | Numeric macros, parameters, relative include graphs, constant expressions, generate-for, constant generate-if/else, connected hierarchy flattening | Positive preprocessing/include/hierarchy/generate fixtures plus typed include and recursive-hierarchy failures | Smoke checked |
| RTL IR | Contract defined | Processes, expressions, typed case/latch statements, clock-edge metadata, registers, memories, ports, connectivity | Parser and snapshot tests | Smoke checked; downstream lowering remains explicitly blocked where semantics are not preserved |
| Gate-design IR | Contract defined | Structural cell/pin/net parser, reverse connectivity and validator | Gate parser and negative connectivity tests | Smoke checked |
| Round-trip serialization | Contract defined | Canonical JSON snapshot codec with schema/digest verification | Round-trip and tamper tests | Smoke checked |
| UPF and CPF parsing | Contract defined | Native policy subset | UPF/CPF fixtures | Smoke checked |
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

The package goal is complete only when every P0 function has a concrete backend, structured failure behavior, retained corpus, reference correlation where an oracle exists, process-scoped qualification where required, a deterministic CLI and a passing Xcircuite headless integration test.

## Current blockers

- Full SystemVerilog, UPF and CPF language semantics remain outside the native subset and return blocked diagnostics.
- No external-tool adapter has been selected or qualified.
- No process-specific corpus has been retained.
- Full Xcircuite regression is pending current-worktree revalidation because concurrent SwiftPM dependency builds are active and the shared graph has an unresolved DFTEngine `PDKReference` boundary. The retained multi-engine signoff-artifact and approval/resume path remains focused evidence only; production PEX, independent oracle correlation and process qualification remain open.
- The LogicEngine lowering slice now consumes the canonical `LogicDesignReference.designDigest` for RTL snapshots while retaining `artifact.sha256` for serialized-byte integrity.

This file must be updated by implementation agents whenever a maturity gate changes. A source file or type name alone is never evidence of implementation or qualification.
