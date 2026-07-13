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

Status: in progress. Snapshot/request validation, canonical-vs-serialized digest separation, adapter artifact integrity gates, and a retained lowering-to-simulation-to-timing-to-physical handoff are implemented; full signoff-chain coverage remains.

## Milestone 2: Deterministic HDL and power-intent semantics

Exit criteria:

- The supported SystemVerilog subset is expanded in vertical slices: preprocessing, constant elaboration, procedural statements, expressions, hierarchy, and diagnostics.
- UPF and CPF semantics are modeled with source spans, stable IDs, reference validation, and explicit unsupported-command boundaries.
- Each new semantic has positive, negative, and round-trip corpus coverage.

Status: in progress. Numeric macro/timescale preprocessing, object-like conditional compilation, relative include graph resolution, contextual constant generate, symbolic ranges, parameterized hierarchy, connected hierarchy flattening and source-ordered clock/asynchronous-reset events are executable native slices; malformed, missing, recursive hierarchy, cyclic includes, unresolved parameter contexts and unterminated conditionals produce typed diagnostics. Bidirectional ports and non-identifier output connections remain explicit blocked boundaries. Case statements and latch processes are retained in RTL IR but remain blocked by lowerers that cannot preserve their semantics. Function-like or expression-valued macros and wider procedural coverage remain.

## Milestone 3: Cross-engine design identity

Exit criteria:

- RTL, gate, synthesized, DFT-transformed, timing, and physical handoffs retain input digest, source identity, top design, and transformation provenance.
- Gate connectivity validates drivers, loads, port directions, widths, hierarchy, and stable IDs.
- Consumers can load canonical artifacts without UI or ad-hoc conversion.

Status: in progress. Gate reverse connectivity and direction validation, the RTL-snapshot-to-lowering digest boundary, and a shared `LogicDesignProvenance` handoff contract are implemented. Native LogicEngine lowering/synthesis, DFTEngine scan/BIST, and Xcircuite elaboration producers attach lineage. TimingEngine signoff analysis, PhysicalDesignEngine execution, and ReleaseEngine signoff now validate supplied lineage and fail closed on invalid or mismatched provenance; remaining handoff consumers and full signoff-chain evidence remain.

## Milestone 4: Xcircuite execution and human-in-the-loop

Exit criteria:

- Stage adapters resolve and verify inputs, evaluate trust gates, persist raw and canonical artifacts, and attach provenance.
- Stage results participate in approval, review, resume, cancellation, and repair-loop flows.
- Headless integration tests execute against a working dependency graph and assert artifact integrity.

Status: LogicDesign and focused Xcircuite adapters are verified by headless tests. The retained `EndToEndDesignFlowTests/retainedMultiEngineRunResumesAfterReview` flow defines lowering, logic simulation, STA, physical floorplanning, native DRC/LVS, deterministic mock PEX, immutable review-packet validation, human approval, and same-run resume. The latest complete scratch regression executed 537 tests in 58 suites but failed 6 active DFT release/qualification runtime assertions. Mock PEX is contract evidence rather than physical signoff, and real PEX environment execution, oracle and process qualification remain separate gates.

## Milestone 5: Qualification and release eligibility

Exit criteria:

- Retained positive/negative corpus is versioned and reproducible.
- External oracle correlation is recorded where an oracle exists.
- Process/PDK-scoped qualification records include tool, version, inputs, outputs, metrics, and failures.
- Tool trust and release gates prevent unqualified results from being treated as signoff.

Status: in progress for the qualification machinery; no external-oracle or foundry/process qualification is claimed. Tool evidence, local corpus/oracle comparison, exact scope matching at release-profile eligibility, freshness, independence, and release gates exist as typed contracts, while a retained process-scoped evidence record is still required.

## Execution policy

Work proceeds in vertical slices. A slice is not promoted by parser success alone: its artifact, diagnostic, corpus, integration, and qualification evidence must be updated together. Existing user changes in other packages remain untouched unless a dependency boundary explicitly requires a compatible fix.
