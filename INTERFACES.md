# LogicDesign Interface Contract

## Common shape

```swift
public protocol DomainExecuting: Sendable {
    func execute(
        _ request: DomainRequest
    ) async throws -> XcircuiteEngineResultEnvelope<DomainPayload>
}
```

Requests carry a schema version, run ID and typed artifact references. Payloads contain domain metrics only. Diagnostics and artifacts belong to the shared envelope.

### Design identity and serialized integrity

`LogicDesignReference.designDigest` identifies the canonical design content. `LogicDesignReference.artifact.sha256` and `byteCount` identify and protect the serialized artifact bytes. Snapshot consumers must validate both boundaries: decode and verify the canonical snapshot digest, then verify the referenced artifact bytes before execution.

Transformed handoffs may carry `LogicDesignReference.provenance`. It preserves the original canonical source digest, immediate input digest, stable transformation ID, producer identity/version and run ID. `topDesignName` remains part of the reference so consumers can reject cross-top handoffs.

## Products

### LogicIR

Stable RTL and gate-design identity.

### SystemVerilogFrontend

Parsing and elaboration.

### PowerIntent

UPF and CPF semantics.

### LogicDesign

Umbrella API.


## Error contract

- Throw only when execution cannot produce a valid result envelope.
- Represent design findings and failed checks as typed diagnostics and a completed domain payload.
- Represent missing prerequisites or insufficient semantics as `blocked`.
- Preserve cancellation as `cancelled`.
- Do not swallow parser, process or persistence failures.

## Xcircuite adapter

The adapter must:

1. resolve project-relative references through XcircuitePackage;
2. verify input digests;
3. evaluate ToolQualification requirements;
4. invoke the injected engine protocol;
5. persist every returned artifact;
6. map diagnostics and status to FlowStageResult;
7. attach design, PDK and tool provenance;
8. leave approval and resume handling to DesignFlowKernel.

The native LogicDesign adapters persist canonical artifacts in the run package, include those references in the engine envelope, persist the envelope through `XcircuitePackageStore`, and add an artifact-integrity gate to the resulting flow stage.
