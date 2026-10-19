# SourceText

## Purpose and Scope
Own immutable lexical text and projection from transformed byte offsets to exact
input artifact ranges. Parent: [Frontend](../DESIGN.md). No children. This is a
source owner contract, not a preprocessor or content-digest implementation.

## Responsibilities and Boundaries
Retain exact root and segment documents and original artifact references, optionally own expanded UTF-8 bytes and ordered origin
segments, and expose scoped borrowed bytes. No file lookup, hashing, macro
expansion, grammar or circuit semantics. Exact documents remain unchanged.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Frontend](../DESIGN.md) | parent | Portable source composition | Text owner | Expansion is separately owned |
| [SourceModel](../../LogicIR/SourceModel/DESIGN.md) | depends on | LogicSourceDocument | Exact root document | Host verifies source digest |
| [LexicalAnalysis](../LexicalAnalysis/DESIGN.md) | used by | Scoped text bytes and origin projection | Token byte offsets | Transformed offsets are not artifact offsets |
| [SyntaxParsing](../SyntaxParsing/DESIGN.md) | used by | Retained immutable text | Symbol bytes and diagnostics | Do not synthesize an ArtifactID for expanded text |

## Architecture
```text
Exact document ----------------------> identity text view
Exact documents + expanded segments -> transformed immutable text owner
                                        -> borrowed bytes -> tokens / symbols
                                        -> origin(range) -> exact artifact range
```

## Contracts and Invariants
SystemVerilogSourceText is a Sendable immutable value retaining one exact root.
Identity views borrow the root bytes without materializing them. Transformed
owners retain bytes plus an ordered, gap-free segment table. Every segment maps
to one validated exact artifact range, either by equal-length byte correspondence
or by an expansion-site anchor. Exact mappings are compared against their retained
source document bytes before publication; length agreement alone is insufficient. Empty expanded text retains a validated explicit
EOF origin. Publication validates counts, bounds and mapping shape before access.
The transformed owner has no content ArtifactID: root identity never claims that
expanded bytes are the exact root bytes.

Ranges within an exact segment preserve their byte displacement. Ranges within
an anchor map to the full expansion site. Multi-segment ranges use the first
segment's location and extend through the last only when all participating
segments belong to the same artifact and their origins are ordered. Otherwise
the first exact location is used; the source owner retains the full segment map.
EOF maps to the explicit terminal origin. All lexer, literal, syntax and semantic
failures and emitted IR origins use this one projection contract.

## State, Ownership, and Lifecycle
Private immutable final storage owns transformed arrays. Exact source storage
retains its existing owner. A scoped Span never escapes or crosses suspension.
Published payload capacity and segment validation consume the shared invocation
context; input and output owners overlap and are charged independently. Identity
views allocate no byte or segment arrays. No shared mutable state is introduced.

## Failure, Concurrency, and Constraints
Reject malformed UTF-8, gaps, overlaps, empty segments, unequal exact mapping,
invalid terminal origins and arithmetic overflow. Origin lookup validates its
range before indexing and uses binary search over the immutable segment table.
No platform branch weakens ownership or Sendable. Counts and payload bytes are
bounded by the caller's shared kernel limits; allocator metadata is not measured.

## Verification and Change Impact
SourceTextTests verifies exact byte borrowing, identity ranges, anchor ranges,
cross-artifact boundaries, EOF, invalid maps/UTF-8 and cumulative resource/cancel
failure. Lexer/literal/parser and published expression/process diagnostics must
retain the original artifact and valid byte range after text expansion. Portable
probes execute these paths on Native/WASM/Embedded with fixed toolchain/SDK.
Changing projection requires rechecking all frontend origin consumers and host
source diagnostics; source mapping tests alone establish no macro semantics.

The package-only origin-segment callback projects clipped ranges without
materializing an intermediate segment array. SourcePreprocessing uses it when
concatenating included and expanded text; exact byte validation remains mandatory.
