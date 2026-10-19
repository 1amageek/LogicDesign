# Portable floor migration from public d13cebf

## Scope and source authority

This isolated candidate uses the complete existing LogicDesign implementation at
1756c4ef9a79f754aec307fa293b2d00bda66faa, the earliest coherent revision containing
the required Boolean operations, node indices, four-state scalar, validated Boolean
builder and portable kernel. It does not mix the old host LogicIR with new portable
values. Production Swift bodies are unchanged. The only manifest change selects
public CircuiteFoundation 5f132c58209123433e0e479e1ea61096e46061ba.
MIT licensing of LogicDesign-owned code was explicitly authorized on 2026-10-19.
Separate dependency licenses and notices remain with their original sources.

## Products and consumer migration

All original d13cebf public product names remain: LogicIR, SystemVerilogFrontend,
PowerIntent, LogicDesign and logic-design. LogicKernelCore and
LogicDesignSerialization are added. Product retention is not source compatibility.

| Public d13 usage | Coherent floor usage | Actual compatibility effect |
|---|---|---|
| LogicIR with Codable/JSON/digest/netlist APIs | Add LogicDesignSerialization product/import at host boundary | Codable conformances and GateNetlistParser, LogicDesignSnapshotCodec, LogicSourceDigest, StableLogicID move out of portable LogicIR |
| SystemVerilogFrontend legacy parser/async Engine/source providers | Import LogicDesign host product | Legacy implementations remain under LogicDesign; portable frontend no longer exposes those host dependencies |
| Draft hierarchy identity generated inside IR | Supply LogicDraftIdentityGenerating; host may use StableLogicID | Explicit identity authority replaces hidden host hashing |
| Legacy GateModule decoding without portBindings | Explicit required portBindings in host decoder | Prior name/id-based inference is refused; original ValidationTests exercises this boundary |
| Native-only toolchain assumption | Swift 6.4, Span requires macOS 26 | Whole package's old macOS 14 platform declaration does not make Span available there |

LogicDesignReference constructors retain artifact, canonical digest and provenance
fields; LogicDesignProvenance retains schema/version/canonical material. Portable
validation uses Character.isWhitespace rather than Foundation trimming. Snapshot
host decoding validates the decoded RTL/gate models and throws validationFailed for
errors; it is not a raw unchecked DTO decoder. These are intentional source and
admission changes from the existing coherent implementation, requiring an explicit
publication/version decision rather than a silent patch-version compatibility claim.

## Exact dependency and qualification boundaries

The consumed public CF Core, Serialization, Foundation conversion and Crypto source
directories are byte-identical to the primary c952ac5 dependency. Its manifest removes
a Linux-only libm linker setting; Native macOS evidence cannot qualify Linux.
No Foundation host product enters the portable LogicIR/LogicKernelCore dependency
closure. The resolver may fetch swift-crypto transitive sources for the full graph;
they retain their separate licenses and are not vendored in this archive.

Original focused contracts are CellFunctionTests (3), FourStateValueTests at this
revision (6), SerializationBoundaryTests (5), and ExecutionControlTests (10): 24
methods. All other original tests remain in the candidate. Focused success will
qualify only the exercised consumed lower contracts, not all frontend/CLI/host or
LogicEngine behavior. Actual Timing integration and any broader claimed package
scope require their own execution evidence. Existing historical evidence is kept
outside this archive; it is not relabeled as this candidate's public-pin runtime.

No branch, commit, tag, remote or primary source has been changed by candidate
preparation. This archive is not published or qualified until its recorded commands
succeed and the owner selects the public branch/version path.
