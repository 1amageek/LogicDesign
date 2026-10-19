# SystemVerilogFrontend

## Purpose and Scope

Portable synchronous SystemVerilog processing. Parent: [LogicDesign](../../DESIGN.md).
Children: [SourceElaboration](SourceElaboration/DESIGN.md), [SourcePreprocessing](SourcePreprocessing/DESIGN.md), [SourceText](SourceText/DESIGN.md), [LexicalAnalysis](LexicalAnalysis/DESIGN.md), [IntegerLiterals](IntegerLiterals/DESIGN.md), [SyntaxParsing](SyntaxParsing/DESIGN.md), [ParameterBinding](ParameterBinding/DESIGN.md), [ConstantEvaluation](ConstantEvaluation/DESIGN.md), [InstanceParameters](InstanceParameters/DESIGN.md), [StaticScopes](StaticScopes/DESIGN.md), [StaticControl](StaticControl/DESIGN.md), [ExpressionResolution](ExpressionResolution/DESIGN.md), [ProgramElaboration](ProgramElaboration/DESIGN.md). Public resolved elaboration composes its verified child contracts; lexical
success alone is not an ElaboratedRTL result.

## Responsibilities and Boundaries

Consume exact source bundles, retain source origins, and own language admission.
Host acquisition, hashing, JSON and asynchronous Engine composition live in
LogicDesign. Legacy draft parsing remains explicitly host-only during migration.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicDesign](../../DESIGN.md) | parent | host composition | package owner | no upward package dependency |
| [SourceModel](../LogicIR/SourceModel/DESIGN.md) | depends on | exact UTF-8 byte ownership | input | host verifies digests |
| [LogicKernelCore](../LogicKernelCore/DESIGN.md) | depends on | cumulative context | control and limits | no stage budget reset |
| [SourceElaboration](SourceElaboration/DESIGN.md) | child | SystemVerilogElaborating | public source-to-RTL composition | language profile and caller capacities are explicit |
| [SourcePreprocessing](SourcePreprocessing/DESIGN.md) | child | exact-bundle compiler directives and macro expansion | lexical text composition | no filesystem or implicit path search |
| [SourceText](SourceText/DESIGN.md) | child | immutable transformed text and exact origin projection | source-position authority | transformed bytes have no exact input ArtifactID |
| [LexicalAnalysis](LexicalAnalysis/DESIGN.md) | child | bounded tokens | syntax scanning | tokens are not semantic admission |
| [IntegerLiterals](IntegerLiterals/DESIGN.md) | child | arbitrary-width decoding | synthesis literal admission | no Int64 fallback |
| [SyntaxParsing](SyntaxParsing/DESIGN.md) | child | flat source-retaining syntax | portable grammar | semantic resolution is separate |
| [ParameterBinding](ParameterBinding/DESIGN.md) | child | module-local parameter references | declaration-position admission | no computed values or full module acceptance |
| [ConstantEvaluation](ConstantEvaluation/DESIGN.md) | child | typed integral defaults | width/sign and packed indexing | no hierarchy/process acceptance |
| [ProgramElaboration](ProgramElaboration/DESIGN.md) | child | selected hierarchy and ordered programs | whole-program RTL composition | success requires validated publication and behavioral proof |
| [ExpressionResolution](ExpressionResolution/DESIGN.md) | child | shared typing and explicit RTL expressions | runtime signal expressions | complete program publication remains composition-owned |
| [StaticControl](StaticControl/DESIGN.md) | child | binary generate and static loop control | selected syntax and explicit iteration lifecycle | body execution remains composition-owned |
| [StaticScopes](StaticScopes/DESIGN.md) | child | immutable lexical constants | selected block/iteration environments | no loop unrolling or RTL publication |
| [InstanceParameters](InstanceParameters/DESIGN.md) | child | exact instance parameter composition | named/ordered parent-to-child assignments | no port or generate-scope elaboration |

## Architecture

```mermaid
flowchart LR
  Bundle[Exact source bundle] --> Preprocessing[Exact-bundle preprocessing]
  Preprocessing --> Lexical[Byte-range lexical analysis]
  Lexical --> Parser[Subset syntax parsing]
  Parser --> Parameters[Parameter reference binding]
  Parameters --> Resolve[Type/value/hierarchy elaboration]
  Resolve --> RTL[Resolved RTL]
```

## Contracts and Invariants

Only Standard Library, LogicIR, LogicKernelCore and CircuiteFoundation Core are
portable dependencies. Source errors retain the exact artifact and byte range.
No token kind or spelling implies accepted synthesis semantics.

## Verification and Change Impact

Focused source/lexical tests and portable runtime probes exercise actual admission,
byte offsets and resource/cancellation failures. Changes require rechecking the
parser and host source acquisition path. Lexical success establishes no elaboration,
synthesis, simulation or proof guarantee.
