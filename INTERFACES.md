# LogicDesign Interface Contract

LogicDesign publishes typed digital-design schemas and protocols.  It is
usable in-process or by an external tool and does not depend on Xcircuite,
DesignFlowKernel, or a filesystem runtime.

## Common execution shape

```swift
public protocol Engine<Request, Output>: Sendable {
    associatedtype Request: Sendable
    associatedtype Output: Sendable

    func execute(_ request: Request) async throws -> Output
}
```

`SystemVerilogFrontend` and `PowerIntent` refine
`CircuiteFoundation.Engine` directly. Each product defines its own request and
result type. A result contains the
domain payload, `DesignDiagnostic` values, `ArtifactReference` values, and
`ExecutionProvenance` needed to reproduce the execution.

Requests carry a schema version and explicit `ArtifactLocator` inputs.  A
backend resolves locators through its injected source provider and emits
immutable artifact references with a digest, byte count, role, kind, and
format.

`PowerIntentDesign` schema version 2 retains directives only through
`structuredDirectives: [PowerIntentDirective]`. The former raw string
projection is no longer part of the canonical artifact, and version 1 power
intent artifacts are rejected rather than silently reinterpreted.

The SystemVerilog parser emits `typedCaseStatement` values for standard,
`casex`, and `casez` semantics. The IR has no untyped compatibility case.

## Capability inspection

`logic-design capabilities` emits `LogicDesignCapabilityReport` schema version
2. Its `capabilities`, `blockedSemantics`, and `validationChecks` describe the
package's executable surface. `LogicDesignEvidenceBoundary.producedEvidence`
describes package outputs, while `externalDecisions` identifies decisions made
by ToolQualification, process policy, or release authorization. The report has
no qualification status and schema version 1 is rejected.

## Design identity and integrity

`LogicDesignReference.designDigest` identifies canonical design content.
`LogicDesignReference.artifact` identifies the serialized snapshot.  Consumers
must validate the canonical design digest and then verify the referenced bytes
before execution.  Transformed handoffs preserve source digest, immediate input
digest, transformation identity, producer version, and run context in the
domain provenance record.

## Products

| Product | Responsibility |
| --- | --- |
| LogicIR | Portable draft values and validated bit graph owners. |
| LogicKernelCore | Shared synchronous invocation control and cumulative budgets. |
| LogicDesignSerialization | Explicit host coding and validated graph decoding. |
| SystemVerilogFrontend | Parsing, preprocessing, and elaboration. |
| PowerIntent | UPF and CPF semantics. |
| LogicDesign | Umbrella module that exports the public contracts. |

## Error contract

- Throw a typed error only when execution cannot produce a valid domain result.
- Represent findings and failed checks as `DesignDiagnostic` values in a
  completed result.
- Represent missing prerequisites or unsupported semantics as a blocked result.
- Preserve cancellation as a cancelled result or typed cancellation error.
- Never swallow parser, process, or persistence failures.

## Integration boundary

LogicDesign exposes protocols and value types only.  Xcircuite may provide a
flow-stage implementation that invokes these protocols, while DesignFlowKernel
owns run lifecycle, approval, resume, and policy.  Xcircuite owns concrete
`.xcircuite` persistence.  ToolQualification evaluates tool capability and
trust independently from the engine result.

The LogicDesign package itself remains independently usable and exposes only
its canonical domain protocols and value types.

## LogicKernelCore

The shared portable kernel contract is owned below the frontend in this package,
not in LogicEngine. [ExecutionControl](Sources/LogicKernelCore/ExecutionControl/DESIGN.md)
owns LogicKernelLimits, the noncopyable LogicKernelContext, typed kernel failures,
exact-artifact source ranges and the LogicRunControlling requirement. Every
calculation stage must consume the same context. Limits have no implicit production
default; every resource is explicit and positive. Native cancellation uses Mutex
and requires macOS 15. Host deadlines implement the same synchronous requirement.

The portable executables exercise cumulative failure, storage ownership and shared
cancellation. Run `swift run LogicKernelPortabilityProbe`; ordinary WASM uses the
matching release SDK and the same product. Embedded uses
`LogicKernelEmbeddedPortabilityProbe` with the matching Embedded SDK, whose manifest
links the required Unicode tables. Successful execution prints
`LOGIC_KERNEL_CONTRACT_OK`. This is kernel-contract evidence, not synthesis or
functional-proof qualification.


## Portable IR and Host Codecs

[LogicIR](Sources/LogicIR/DESIGN.md) defines circuit values. Import
`LogicDesignSerialization` and depend on that host product to use Codable,
LogicSourceDigest, StableLogicID, LogicDesignSnapshotCodec or structural netlist
I/O. The legacy draft elaborators require a `LogicDraftIdentityGenerating` provider;
`StableLogicID()` preserves historical host-generated identifiers. Graph kernels
use canonical entity IDs and dense indices instead.

[BitGraph](Sources/LogicIR/BitGraph/DESIGN.md) owns validated `BitLogicDesign`
publication. `BitLogicDesignCodec` schema v1 decodes through that same builder.
Legacy snapshot schema v1 is still a draft contract, never a mapped functional
proof. New schema-v2 stage handoff is pending runtime migration.

Span borrowing requires macOS 26 on Darwin. The probe prints
`LOGIC_IR_VALUE_CONTRACT_OK` and `LOGIC_BIT_GRAPH_CONTRACT_OK` only after executing
wide bit-plane, topology, exhaustive small-circuit and rejection paths. WASI is
sequential evidence; Native concurrent cancellation is a separate kernel test.


## Portable Word and Source Contracts

`WordLogicDesign` is a validated immutable stage owned by LogicIR, constructed only
through `WordLogicBuilder.finish`. Typed opcode sizing and state assumptions are
normative in [WordGraph](Sources/LogicIR/WordGraph/DESIGN.md). Operation expansion
and expression scheduling are subsequent lowering contracts.

`LogicSourceDocument` retains host-verified exact UTF-8 bytes and `ArtifactID`;
`LogicSourceBundle` rejects duplicate logical names. Source ownership is normative
in [SourceModel](Sources/LogicIR/SourceModel/DESIGN.md). The portable
`SystemVerilogTokenizing` requirement and synthesis literal decoding requirement
use a shared inout LogicKernelContext and typed LogicKernelError. Their guarantees
are defined in [SystemVerilogFrontend](Sources/SystemVerilogFrontend/DESIGN.md).

Legacy `SystemVerilogParser`, source providers, include resolver, draft DTOs and
`LogicElaboratingEngine` now belong to the host `LogicDesign` product. Consumers
adopting this revision import LogicDesign for that migration surface. The portable
SystemVerilogFrontend product exports no Foundation/serialization/Engine types.
Legacy draft results are not ElaboratedRTL and cannot establish functional proof.


## Resolved Procedural RTL

`ElaboratedRTL` owns an immutable, typed procedural program with canonical top ID,
flat expression/statement/case tables, ordered blocking/NBA, explicit clock/reset
roles, four-state constants, dynamic selection and exact origins. Construction
uses `ElaboratedRTLBuilder` and validation; details are normative in
[ResolvedRTL](Sources/LogicIR/ResolvedRTL/DESIGN.md). Initial synthesis-profile
admission and procedural conversion remain separate from program publication.
This type is not produced by the retained legacy draft parser or old Engine.


The package-internal [SyntaxParsing](Sources/SystemVerilogFrontend/SyntaxParsing/DESIGN.md)
component retains flat module/parameter/port, expression, procedural and generate
syntax with bounded nesting and exact source ranges. It does not publish an
elaboration conformance; resolved symbol/width/state admission remains pending.

The package-internal [ParameterBinding](Sources/SystemVerilogFrontend/ParameterBinding/DESIGN.md)
component consumes that syntax owner before constant/type evaluation. Its narrow
binding contract does not publish a public elaboration conformance.

The package-internal [ConstantEvaluation](Sources/SystemVerilogFrontend/ConstantEvaluation/DESIGN.md)
component evaluates bound integral defaults before hierarchy/process elaboration.
It owns language sizing and packed-index semantics while LogicIR owns limb operations.

Module-local instance parameter assignments are composed by the package-internal [InstanceParameters](Sources/SystemVerilogFrontend/InstanceParameters/DESIGN.md) contract. Its immutable parent-expression handles preserve child-context evaluation; this stage does not publish resolved hierarchy or port connectivity.

`SystemVerilogTokenStream.source` retains immutable `SystemVerilogSourceText`.
Its `root` is an exact input document; lexical ranges address the text owner, and
`origin(for:)` projects them to exact artifacts. Expanded text has no ArtifactID
claim. The legacy public lexer/literal requirements still accept exact documents.
The authoritative contract is [SourceText](Sources/SystemVerilogFrontend/SourceText/DESIGN.md).

## Actual-cell host interchange

`MappedGateDesignCoding` schema v1 and `MappedGateVerilogCoding` require validated
actual-cell owners and exact library sources. JSON decoding always uses the
MappedGateBuilder validator; structural import reads physical connectivity from
Verilog and accepts only the documented flat scalar profile. Identity sidecars
retain canonical entity IDs. Specified abstract state initialization is refused
at the standard Verilog boundary because current cells have no power-up guarantee;
JSON preserves abstract initialization demands. Neither format conveys
checked proof authority. [Codec](Sources/LogicDesignSerialization/Codec/DESIGN.md)
owns admission and negative verification.
