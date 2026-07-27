# LogicDesign Design

## Purpose

Canonical digital design, dataflow/process graph, SystemVerilog frontend and power-intent contracts.

## Responsibility boundary

This package owns the schemas and engine protocols listed in its public products. It must remain usable without UI state and without the Xcircuite runtime.

`LogicDataflowDesign` is external-independent. It owns typed SSA operations, values, process state, channel
transport policy and validation, but no XLS syntax or runtime behavior. XLS spelling and textual parsing belong
to `EDAInteroperability/XLSInteroperability`, whose dependency points toward this package.

## Non-responsibilities

- Functional simulation
- Logic optimization or technology mapping
- Timing analysis

## Dependency direction

```text
standard artifacts / canonical references
                 ↓
LogicDesign protocols and result schemas
                 ↓
native or external-tool backends
                 ↓
Xcircuite composition and stage execution
                 ↓
DesignFlowKernel and .xcircuite artifacts
```

Backends may depend on lower-level data packages. This package must never import `Xcircuite` or `circuit-studio`.

## Trust model

Kernel availability, corpus validation, oracle correlation, process-scoped qualification and release approval are distinct states. The package reports capabilities, blocked semantics, validation checks and evidence boundaries. ToolQualification owns tool-trust qualification, while Xcircuite applies flow policy and ReleaseEngine owns release authorization.

## Artifact requirements

All outputs are immutable run artifacts with format, digest, producer metadata and the input design/PDK revision needed to reproduce the result.
