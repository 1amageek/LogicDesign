# LogicDesign Design

## Purpose and Scope

Canonical digital design, dataflow/process graph, SystemVerilog frontend and power-intent contracts. Parent: [LSI system](../DESIGN.md). Child module contracts are indexed in Related Designs.

## Responsibilities and Boundaries

This package owns the schemas and engine protocols listed in its public products. It must remain usable without UI state and without the Xcircuite runtime.

`LogicDataflowDesign` is external-independent. It owns typed SSA operations, values, process state, channel
transport policy and validation, but no XLS syntax or runtime behavior. XLS spelling and textual parsing belong
to `EDAInteroperability/XLSInteroperability`, whose dependency points toward this package.

## Non-responsibilities

- Functional simulation
- Logic optimization or technology mapping
- Timing analysis

## Architecture

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

## Contracts and Invariants

Kernel availability, corpus validation, oracle correlation, process-scoped qualification and release approval are distinct states. The package reports capabilities, blocked semantics, validation checks and evidence boundaries. ToolQualification owns tool-trust qualification, while Xcircuite applies flow policy and ReleaseEngine owns release authorization.

## Artifact requirements

All outputs are immutable run artifacts with format, digest, producer metadata and the input design/PDK revision needed to reproduce the result.

## Portable Kernel Contract Ownership

The approved synthesis redesign places `LogicKernelCore` in this package. It owns
run-local cumulative resource accounting, typed kernel failures and the synchronous
run-control requirement. Both the frontend and LogicEngine depend downward on it.
It depends only on CircuiteFoundation Core and the Swift standard library. This
corrects the proposed frontend-to-LogicEngineCore package cycle; LogicDesign must
not depend on LogicEngine. Domain values remain owned by LogicIR.

```mermaid
flowchart BT
  Frontend[SystemVerilogFrontend] --> Kernel[LogicKernelCore]
  Engine[LogicEngine kernels] --> Kernel
  Engine --> IR[LogicIR]
  IR --> Kernel
  Kernel --> Foundation[CircuiteFoundation Core]
```

The normative lower contract is [LogicKernelCore](Sources/LogicKernelCore/DESIGN.md).
Legacy Foundation/serialization dependencies are being migrated and are not yet
portable-target evidence. New callable contracts are verified before being reported
as implemented. The task's only progress record is [PROGRESS.md](../PROGRESS.md).

The two verification executables provision a 4 MiB WASM linear-memory stack for
their debug frontend profile (maximum nesting 100). The SDK's default 64 KiB
stack fails the composed program path; disassembly measured 15,520-byte lvalue
and 13,488-byte statement frames in this exact debug artifact. Stack provisioning
belongs to the embedding executable, independently of managed heap admission.
The Node verification host separately provisions a 4 MiB execution stack; its
default stack rejects 94 nested blocks even with the linear-memory stack enlarged.
The profile must execute deep accepted syntax and reject a smaller nesting limit
on each target. These linker settings do not propagate into library products.
The historical `logic-program-elaboration` evidence is retained privately outside
the distributed source tree; it records the failed/default-stack and explicitly
provisioned runtime observations at their original source revision.

## Portable IR and Host Serialization Boundary

[LogicIR](Sources/LogicIR/DESIGN.md) owns portable values and validation.
[LogicDesignSerialization](Sources/LogicDesignSerialization/DESIGN.md) owns explicit
host coding, byte/digest conversion and standard structural-netlist I/O. Existing
mutable RTL/Gate parse drafts do not establish elaborated, lowered or mapped-stage
invariants. Consumers that serialize these values explicitly import the host product. The
legacy frontend host execution surface still imports it during consumer migration;
new synchronous frontend and calculation kernels must not depend on it.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LSI](../DESIGN.md) | parent | system composition | independent package | raw evidence is not approval |
| [LogicKernelCore](Sources/LogicKernelCore/DESIGN.md) | child | shared context | portable invocation control | no upward engine dependency |
| [SystemVerilogFrontend](Sources/SystemVerilogFrontend/DESIGN.md) | child | portable source processing | resolved source elaboration | accepted synthesis profile is explicit |
| [LogicDesign host module](Sources/LogicDesign/DESIGN.md) | child | source acquisition and host execution | legacy migration surface | draft success is not synthesis proof |
| [LogicIR](Sources/LogicIR/DESIGN.md) | child | draft and validated values | circuit meaning | draft validation is not proof |
| [LogicDesignSerialization](Sources/LogicDesignSerialization/DESIGN.md) | child | host encoding and decoding | byte boundary | decode validated graphs through builders |

The [SystemVerilogFrontend](Sources/SystemVerilogFrontend/DESIGN.md) owns portable
source processing. Legacy draft parsing and asynchronous execution move to the
[LogicDesign host module](Sources/LogicDesign/DESIGN.md). Their existing
[interface contract](INTERFACES.md) remains a draft contract, not resolved RTL.
PowerIntent retains its host dependency boundary.

Resolved declaration semantics are owned by [ResolvedRTL](Sources/LogicIR/ResolvedRTL/DESIGN.md)
and bound by [ProgramElaboration](Sources/SystemVerilogFrontend/ProgramElaboration/DESIGN.md).
Expression width/sign alone does not describe variable/net initialization or writes.

## Verification and Change Impact

LogicDesignTests own parser fixtures, legacy byte correlation and host codec
admission. LogicKernelCoreTests own invocation control. Portable probe executables
exercise lower contracts on Native, WASM and Embedded WASM. Evidence is retained
in `.verification/logic-kernel-core` and `.verification/logic-ir`; its scope does
not establish synthesis, symbolic proof, process qualification or release approval.
Host products that persist LogicIR values must explicitly depend on
LogicDesignSerialization when adopting this package revision. That dependency
must never be propagated to portable calculation targets.

### Foundation revision compatibility

The exact `c952ac5ebe3c21bf0cbd6d6ac239130efd732b3a` dependency preserves the
consumed Core, Foundation conversion and Crypto source contracts from
`ae88104c556f5802819713ed741f5b2fffffc2d9`; its platform-link addition applies
only to Linux. LogicDesign does not consume the changed FileSystem product.
The package's production and test sources remain unchanged from `8dac4be`.
Existing portable-kernel and codec evidence retains its original scope.
Native dependency adoption verifies snapshot digest preservation, typed rejection
and missing-source diagnostics through the existing consuming APIs. Exact graph,
source hashes and execution results belong to the
privately retained historical compatibility evidence;
this adoption does not establish process or release qualification.


## Actual-cell Source Prerequisite Publication

This publication selects complete implementation/test/resource bytes from
`743bde6540e751b3861099d4bf327cfb3f47cd56`. Only new private verification logs
absent from the existing public parent are excluded. No selected production or
test body is changed. The existing public MIT license and historical migration
record remain present; dependency and third-party licenses are unchanged.

The required direct selector is canonical public CircuiteFoundation
`5f132c58209123433e0e479e1ea61096e46061ba`. Its consumed Core, host conversion and
Crypto source contracts match the originally selected CF revision; Linux-only
filesystem differences are not a Native qualification claim. A fresh remote
resolution owns the exact lock; mirrors, edited packages and local paths cannot
substitute for public source availability.

The existing [MappedGraph](Sources/LogicIR/MappedGraph/DESIGN.md),
[TechnologyLibrary](Sources/LogicIR/TechnologyLibrary/DESIGN.md) and
[host codecs](Sources/LogicDesignSerialization/Codec/DESIGN.md) own the added
public source contracts. Construction validates real pin functions, exact library
bindings, physical constant/startup policy and derived clock lineage. Codecs
revalidate graph ownership and read actual standard-netlist connectivity. These
contracts grant neither checked functional proof nor timing qualification.

```text
exact source/library facts + one caller-owned context
  -> validated cell library / mapped graph -> actual-function clock lineage
  -> checked host codec boundary -> LogicEngine / Physical consumers
```

The public-parent candidate retains all existing public files, including the
historical migration record. Its public product names remain unchanged. Existing
host-versus-portable import boundaries remain explicit; the new mapped values do
not restore legacy metadata execution contracts in upper consumers.

Native consuming qualification builds the original `LogicDesignTests` product
on the public dependency graph, then runs `MappedGraphTests`,
`TechnologyLibraryTests`, `MappedClockLineageTests`, `MappedGateVerilogNamingTests`
and `StructuralVerilogSourceTests`. They check actual truth tables/physical
connections, source/library identity, startup/tie refusal, derived clock roots,
standard bytes/tampering and cumulative capacity/work/cancellation/refund.
Qualification receipts are outside the source tree. Prior three-target evidence
may be reused only with its exact source/toolchain/SDK joins; no Native result is
relabeled as WASM/Embedded or general package readiness.
