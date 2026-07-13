# LogicDesign Requirements

## Goal

Own the canonical digital design and power-intent state shared by every digital and physical engine.

## Required functions

| Function | Required behavior | Priority |
|---|---|---:|
| SystemVerilog lexical and syntax frontend | Parse source units with stable source locations and structured diagnostics. | P0 |
| Preprocessing and elaboration | Resolve parameters, generate constructs, hierarchy and the selected top design. | P0 |
| RTL IR | Represent processes, expressions, registers, memories, ports and connectivity. | P0 |
| Gate-design IR | Represent mapped cells, pins, nets, hierarchy and stable identities. | P0 |
| Round-trip serialization | Persist canonical design snapshots without losing identity or source provenance. | P1 |
| UPF and CPF parsing | Represent supply sets, voltage domains, isolation, level shifting and retention. | P1 |
| Design validation | Reject unresolved references, illegal connectivity and unsupported semantics explicitly. | P0 |

## Required outcomes

- Simulation, synthesis, verification, DFT, timing and P&R consume the same design identity.
- UI state is never the canonical digital design.
- Unsupported HDL semantics are visible and block dependent stages.

## Common platform requirements

- Public execution surfaces are protocol-first, Sendable and dependency-injected.
- Requests and payloads are Codable, Hashable and schema-versioned.
- Inputs use `ArtifactLocator`; outputs use immutable `ArtifactReference`
  values from CircuiteFoundation.
- Diagnostics contain a stable code, severity, affected entity and suggested actions.
- Unsupported semantics and missing prerequisites produce blocked results.
- Native and external-tool backends conform to identical request and payload schemas.
- Execution capability, corpus validation, oracle correlation, process qualification and release approval remain distinct.
- DesignFlowKernel owns flow construction, artifact registration, qualification
  gates, repair loops, approval, and resume. Xcircuite supplies concrete
  `.xcircuite` persistence through its own protocol conformances.
- The package never imports Xcircuite or circuit-studio.

## Required developer surfaces

- Typed API
- Deterministic JSON CLI
- Positive and negative fixtures
- Contract and parser round-trip tests
- Reference corpus
- Capability and limitation report
- Integration tests that invoke the public protocols from a flow-stage client
