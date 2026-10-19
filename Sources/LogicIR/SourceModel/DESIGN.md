# SourceModel

## Purpose and Scope

Own exact immutable source bytes supplied to the portable frontend. Parent:
[LogicIR](../DESIGN.md). No children.

## Responsibilities and Boundaries

Own UTF-8 validation, logical source names, exact artifact references and scoped
byte borrowing. Host acquisition owns reading and computing/verifying digests.
This component validates byte count, not cryptographic content identity.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicIR](../DESIGN.md) | parent | portable immutable publication | source values | no Foundation |
| [LogicKernelCore](../../LogicKernelCore/DESIGN.md) | depends on | bounded context and exact source range | admission/failure | same invocation budget |
| [SystemVerilogFrontend](../../SystemVerilogFrontend/DESIGN.md) | used by | source byte borrow | syntax input | no filesystem access |

## Architecture

```mermaid
flowchart LR
  Host[Host verified bytes] --> Admission[Count and UTF-8 validation]
  Admission --> Document[Immutable source document]
  Document --> Bundle[Unique logical-name bundle]
  Bundle --> Frontend[Scoped frontend borrowing]
```

## Contracts and Invariants

Documents retain an immutable byte array, nonempty logical name and caller-verified
ArtifactID whose byteCount equals the array count. UTF-8 rejects truncated sequences,
overlong encodings, surrogate scalars and values above U+10FFFF. Source ranges use
UTF-8 byte offsets, independent of display columns. A nonempty bundle has unique
logical names and a retained ordered document table. Names never trigger file I/O.

## State, Ownership, and Lifecycle

Consuming construction transfers arrays into immutable final Sendable storage.
Borrowing retains concrete local owners for the callback lifetime. Empty byte
arrays use Span(). Returning a document shares its immutable owner.

## Failure, Concurrency, and Constraints

Admission reserves logical storage and charges input expansion/work through the
same context before allocation/traversal. Storage remains charged for invocation
lifetime. Invalid bytes/count/name and duplicate logical names fail explicitly.
No target-specific state or concurrency contract exists.

## Verification and Change Impact

Focused source/lexical tests and portable runtime probes exercise actual admission,
byte offsets and resource/cancellation failures. Changes require rechecking the
parser and host source acquisition path. Lexical success establishes no elaboration,
synthesis, simulation or proof guarantee.

The package-visible UTF-8 validator is shared with the frontend transformed-text
owner. It validates bytes without constructing or changing an exact ArtifactID.
Exact document construction and host digest authority remain unchanged.
