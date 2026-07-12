# LogicDesign Milestones

This roadmap treats LogicDesign as the canonical digital-design state for the local semiconductor design platform. A milestone is complete only when implementation, structured failure behavior, retained evidence, and the relevant integration boundary are all verified.

## North-star outcome

Agent and human workflows must be able to create, inspect, modify, verify, review, approve, resume, and hand off one auditable digital-design state across simulation, synthesis, verification, DFT, timing, and physical design. Standard artifacts and canonical IR remain the source of truth; UI state is never authoritative.

## Milestone 0: Requirements and evidence baseline

Exit criteria:

- P0/P1 functions are mapped to public protocols, artifacts, diagnostics, and tests.
- Native implementation, integration, corpus, oracle, process qualification, and release approval are reported separately.
- Every intentional limitation has a stable blocked diagnostic and a suggested next action.
- The dependency direction between LogicDesign and Xcircuite is documented.

Status: complete for the current audit. The gap inventory is recorded in `GOAL_STATUS.md`.

## Milestone 1: Canonical contract and artifact integrity

Exit criteria:

- Requests, payloads, snapshots, references, and envelopes have explicit schema compatibility checks.
- Source and output references are digest-verified and immutable at every Xcircuite handoff.
- Snapshot identity is deterministic across encode/decode and independent of run timestamps.
- Failed, blocked, cancelled, and resumed executions preserve structured evidence.

Status: in progress. Snapshot/request validation, canonical-vs-serialized digest separation, and adapter artifact integrity gates are implemented; orchestrated handoff evidence remains.

## Milestone 2: Deterministic HDL and power-intent semantics

Exit criteria:

- The supported SystemVerilog subset is expanded in vertical slices: preprocessing, constant elaboration, procedural statements, expressions, hierarchy, and diagnostics.
- UPF and CPF semantics are modeled with source spans, stable IDs, reference validation, and explicit unsupported-command boundaries.
- Each new semantic has positive, negative, and round-trip corpus coverage.

Status: in progress. Numeric macro/timescale preprocessing, relative include graph resolution, and constant generate-if/else are executable native slices; malformed, missing, and cyclic includes produce typed diagnostics. Case statements and latch processes are retained in RTL IR but remain blocked by lowerers that cannot preserve their semantics. Conditional compilation, function-like macros, and wider procedural coverage remain.

## Milestone 3: Cross-engine design identity

Exit criteria:

- RTL, gate, synthesized, DFT-transformed, timing, and physical handoffs retain input digest, source identity, top design, and transformation provenance.
- Gate connectivity validates drivers, loads, port directions, widths, hierarchy, and stable IDs.
- Consumers can load canonical artifacts without UI or ad-hoc conversion.

Status: in progress. Gate reverse connectivity and direction validation, the RTL-snapshot-to-lowering digest boundary, and a shared `LogicDesignProvenance` handoff contract are implemented. Native LogicEngine lowering/synthesis, DFTEngine scan/BIST, and Xcircuite elaboration producers now attach lineage; consumer-side enforcement across timing, physical implementation and release approval remains.

## Milestone 4: Xcircuite execution and human-in-the-loop

Exit criteria:

- Stage adapters resolve and verify inputs, evaluate trust gates, persist raw and canonical artifacts, and attach provenance.
- Stage results participate in approval, review, resume, cancellation, and repair-loop flows.
- Headless integration tests execute against a working dependency graph and assert artifact integrity.

Status: LogicDesign and multi-engine adapter slices are verified by headless Xcircuite tests. The full Xcircuite regression passes with 505 tests in 54 suites, including qualification scope mismatch and approval/resume coverage; a single end-to-end multi-engine design run with human review remains incomplete.

## Milestone 5: Qualification and release eligibility

Exit criteria:

- Retained positive/negative corpus is versioned and reproducible.
- External oracle correlation is recorded where an oracle exists.
- Process/PDK-scoped qualification records include tool, version, inputs, outputs, metrics, and failures.
- Tool trust and release gates prevent unqualified results from being treated as signoff.

Status: not started. No foundry or process qualification is claimed.

## Execution policy

Work proceeds in vertical slices. A slice is not promoted by parser success alone: its artifact, diagnostic, corpus, integration, and qualification evidence must be updated together. Existing user changes in other packages remain untouched unless a dependency boundary explicitly requires a compatible fix.
