# LogicDesign Interface Contract

LogicDesign publishes typed digital-design schemas and protocols.  It is
usable in-process or by an external tool and does not depend on Xcircuite,
DesignFlowKernel, or a filesystem runtime.

## Common execution shape

```swift
public protocol DomainExecuting: Sendable {
    associatedtype Request: Sendable & Codable & Hashable
    associatedtype Result: Sendable & Codable & Hashable

    func execute(_ request: Request) async throws -> Result
}
```

Each product defines its own request and result type. A result contains the
domain payload, `DesignDiagnostic` values, `ArtifactReference` values, and
`ExecutionProvenance` needed to reproduce the execution.

Requests carry a schema version and explicit `ArtifactLocator` inputs.  A
backend resolves locators through its injected source provider and emits
immutable artifact references with a digest, byte count, role, kind, and
format.

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
| LogicIR | Stable RTL and gate-design identity. |
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
