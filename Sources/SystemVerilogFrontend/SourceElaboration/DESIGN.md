# SourceElaboration

## Purpose and Scope
Own the public synchronous compilation of an exact source bundle into validated
ElaboratedRTL. Parent: [Frontend](../DESIGN.md). No children. The versioned initial
synthesis profile composes already verified lower language contracts.

## Responsibilities and Boundaries
Validate caller options, compose preprocessing and syntax/program compilation,
and publish only the common-validator-approved RTL. No filesystem acquisition,
source hashing, runtime simulation, word/bit lowering, mapping or host artifacts.
The legacy LogicDesign host Engine remains a separately identified draft path.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Frontend](../DESIGN.md) | parent | public synchronous composition | language admission | no host dependency |
| [SourcePreprocessing](../SourcePreprocessing/DESIGN.md) | depends on | exact roots and transformed origins | compiler directives | explicit preprocessing subset |
| [SourceText](../SourceText/DESIGN.md) | depends on | scoped bytes and segments | compilation-unit concatenation | no invented artifact identity |
| [SyntaxParsing](../SyntaxParsing/DESIGN.md) | depends on | syntax limits and parser | grammar admission | syntax is not resolved meaning |
| [ProgramElaboration](../ProgramElaboration/DESIGN.md) | depends on | selected hierarchy compiler | resolved RTL | retains width/sign/process contracts |
| [ResolvedRTL](../../LogicIR/ResolvedRTL/DESIGN.md) | depends on | capacity and validated publication | immutable result | validator cannot be bypassed |
| [LogicLowering](../../../../LogicEngine/Sources/LogicLowering/DESIGN.md) | used by | ElaboratedRTL | source-to-bit composition | downstream binary admission is separate |

## Architecture
```text
SystemVerilogElaborating requirement
  -> NativeSystemVerilogElaborator
  -> exact-bundle preprocessing
  -> source-position-preserving compilation unit
  -> lexer -> syntax parser -> program compiler -> common RTL validation
  -> immutable ElaboratedRTL
```

## Contracts and Invariants
SystemVerilogElaborating is Sendable, synchronous, typed-throwing and borrows the
bundle/options. NativeSystemVerilogElaborator has no stored mutable state. Its
requirement is callable through an existential on every portable target.
SystemVerilogElaborationOptions.profileIdentifier is systemverilog.synthesis.v1.
Options retain immutable root names, top, token/syntax/RTL capacities and nesting
admission. Positive caller-selected capacities are validated before execution;
resource consumption remains cumulative in the one supplied context.

The profile is the intersection of the following normative child contracts, not
full IEEE 1800 acceptance. Rejected source syntax/semantics retain original source
ranges; invalid caller selection/capacity is a typed input error.

| Language surface | Normative owner |
|---|---|
| Compiler directives, exact includes, object/function macros | SourcePreprocessing |
| Module/declaration/process/expression grammar; unsupported division/remainder/power | SyntaxParsing |
| Packed integral width/sign, literals, parameters/localparams | ConstantEvaluation and ExpressionResolution |
| Selected module hierarchy, static generate/loops, ports, assignments, case, FF/latch controls | ProgramElaboration |

Packages/imports, interfaces/modports, memories, general types, multiple clocks,
mixed FF/latch profiles and synthesis X/Z dependence are refused by the owning
language or graph boundary. Word lowering separately rejects unsupported
procedural/race/driver behavior; elaboration success alone is not synthesis proof.
Ordered roots form one compilation unit. Macro/conditional state persists across
roots, and module syntax can span root boundaries. A generated separator prevents
end-of-file comments and adjacent tokens from merging across those boundaries.
Every copied segment preserves its exact original document; generated separators
anchor to a real byte in their compilation root. Empty roots contribute no bytes.

## Runtime Flows
Preprocess ordered roots, copy them once into a source-position-preserving unit,
lex/parse it, then resolve the requested top and publish through the RTL builder.
Each stage receives the same inout context and checks cancellation/deadline/limits.
No stage restarts the budget or returns a partial successful design.

## State, Ownership, and Lifecycle
The local noncopyable text builder owns mutable unit bytes and segments. Source,
tokens, syntax and RTL retain immutable storage. Scoped Span views cannot escape
or cross suspension. One-element syntax-owner storage is admitted before array
construction. Temporary builder reservations unwind on all throws; immutable
intermediate payload admission is conservative for the invocation lifetime.

## Failure, Concurrency, and Constraints
Caller capacities and context bounds govern preprocessing, tokens, syntax, RTL,
work, storage and output. The caller selects nesting and a qualified execution
stack profile; no hidden default operational limits or stack guarantee are added.
All targets use identical owners, declarations, failure and Sendable contracts.
No new shared state, asynchronous boundary or unsafe access is introduced.

## Verification and Change Impact
PublicSourceElaborationTests exercise the actual public requirement through an
existential, accepted multi-root/include/macro/parameter/hierarchy/process source,
independent observed values, exact failure origins, unsupported input, cumulative
budgets and cancellation. Portable probes execute accepted/refused paths on Native,
ordinary WASM and Embedded WASM. Source-to-word/bit tests are owned by LogicEngine.
Changing lower language or RTL assumptions requires rechecking this composition
and the downstream kernels; passing this boundary is not equivalence evidence.
