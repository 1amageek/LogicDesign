# SourcePreprocessing

## Purpose and Scope
Own bounded, deterministic preprocessing of caller-selected compilation roots from
one exact LogicSourceBundle. Parent: [Frontend](../DESIGN.md). No children. One
ordered root list forms one compilation unit, sharing macro and conditional state.

## Responsibilities and Boundaries
Resolve includes only by exact supplied logical names; expand object/function
macros and conditional directives; preserve source origins. No filesystem, path
search, digest computation, SystemVerilog expression evaluation or RTL semantics.
The host supplies every included document and chooses the root order.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Frontend](../DESIGN.md) | parent | compilation composition | produces lexical text | public elaboration composes parsing separately |
| [SourceModel](../../LogicIR/SourceModel/DESIGN.md) | depends on | exact source bundle | all root/include bytes | no implicit source acquisition |
| [SourceText](../SourceText/DESIGN.md) | depends on | immutable text and origin segments | preserves artifact meaning | expanded bytes have no input content identity |
| [LexicalAnalysis](../LexicalAnalysis/DESIGN.md) | depends on | typed lexical tokens | macro formal replacement | only identifier tokens are substituted |

## Architecture
```text
Exact bundle + ordered roots + nesting limit
  -> exclusive preprocessing workspace
       macro definitions / formal references / conditional frames
       include and macro recursion stacks
  -> bounded source buffers with exact and expansion-site segments
  -> immutable SystemVerilogSourceText roots -> lexer/parser/elaboration
```

## Contracts and Invariants
The initial profile accepts object-like and function-like ASCII macro names,
identifier formals, empty replacement/arguments, nested calls, balanced actual
arguments, multiline definitions, define/undef/undefineall, quoted include names,
and ifdef/ifndef/elsif/else/endif. Macro definitions persist across ordered roots
and included documents. Includes match exact bundle logical names; they perform
no directory probing or path normalization. Missing roots/includes, duplicate
roots, recursive includes/macros, malformed directives/arguments and unmatched
conditionals fail with their original source location.

Macro names and formal references retain source ranges rather than repeatedly
materializing strings. Replacement substitutes identifier tokens outside comments,
strings and numeric tokens, then recursively expands the instantiated text.
Expansion-site anchors point to the invoking exact source; copied file fragments
retain exact byte correspondence. Definition line continuations are removed before
replacement tokenization. Argument usages are substituted literally before nested
macro expansion, without rebinding formal names introduced by nested expansion.
Comments/strings/escaped identifiers protect embedded
backticks. Inactive branches perform no include lookup or macro expansion.

The profile explicitly refuses macro defaults, token pasting, macro quoting,
built-in file/line macros, angle-bracket/computed includes, and compiler directives
created by macro expansion. Other compiler directives are located unsupported
failures. No unsupported construct is silently retained or treated as success.
Scope-specific directives such as timescale/default_nettype await explicit semantic
contracts rather than guessed defaults. Conditional state must balance at the end
of the ordered compilation unit. Included text is separated by the directive's
original line ending when present.

## State, Ownership, and Lifecycle
One noncopyable workspace owns flat macro/formal/conditional/argument/delimiter and
recursion tables. Definitions are retained until invocation end; redefine/undef
changes active membership without publishing mutable state. Source buffers own
byte/segment arrays and a storage reservation, publish through consuming finish,
and release temporary reservations on success and failure. Nested replacement
owners stay alive while their scoped byte borrows are active. No Span escapes or
crosses suspension. All targets share the same state and ownership declarations.

## Failure, Concurrency, and Constraints
The caller supplies nesting admission and cumulative kernel limits. Every scan,
name comparison and expansion charges work. Byte/table growth checks arithmetic
and reserves replacement capacity while old buffers remain charged. Managed
payload counts exclude allocator metadata and call stacks. Nested compilation
requires a stack profile qualified for the selected compiler/optimization and
nesting limit; the package debug executable profile is owned by the package design.
Rescanning retains a bounded contiguous replacement plus caller suffix so function
macro aliases can consume caller argument tokens. This source-layout boundary
copies the suffix and can take quadratic work for repeated nested macro usages;
all copied bytes, retained intermediate texts and overlap are admitted by the same
context. Immutable text payload admission is conservatively cumulative within the
invocation. No zero-copy or performance guarantee is claimed for preprocessing.
Failure publishes no partial preprocessed compilation unit.

## Verification and Change Impact
SourcePreprocessingTests and the portable probe exercise actual expanded text
through parsing/program elaboration and independent observed results. Cases cover
object/function/nested/empty macros, multiline bodies, token-aware substitution,
conditional state across roots/includes, skipped invalid text, include/macro
cycles, located failures, resource/cancellation and immutable source retention.
Recheck SourceText and the public frontend composition when this contract changes.
Preprocessing evidence alone is not word/bit lowering or functional proof evidence.
