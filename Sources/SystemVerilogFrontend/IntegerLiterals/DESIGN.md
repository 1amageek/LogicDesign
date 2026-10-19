# IntegerLiterals

## Purpose and Scope

Own arbitrary-width binary synthesis integer literal decoding. Parent:
[SystemVerilogFrontend](../DESIGN.md). No children. Expression sizing and unary
minus belong to resolved elaboration, not literal decoding.

## Responsibilities and Boundaries

Decode exact source byte ranges without Int64 value truncation or silent zero
fallback. Retain declared signedness and sized/unsized status. Unbased '0/'1
retain a contextual fill marker. X/Z digits are explicitly outside initial
synthesis admission; simulation unknowns are distinct from synthesis constants.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [SystemVerilogFrontend](../DESIGN.md) | parent | subset admission | synthesis literals | not full expression sizing |
| [LexicalAnalysis](../LexicalAnalysis/DESIGN.md) | coordinates with | original source ranges | literal syntax | spaces can separate size/base/digits |
| [LogicValues](../../LogicIR/LogicValues/DESIGN.md) | depends on | exact packed vectors | binary constants | tail bits remain zero |

The [slang grammar](https://github.com/MikePopoloski/slang/blob/master/docs/grammar.md)
and [number parser](https://github.com/MikePopoloski/slang/blob/master/source/parsing/NumberParser.cpp)
are primary implementation cross-checks for IEEE 1800 integer syntax and sizing.
They are validation references, not the execution backend.

## Architecture

```mermaid
flowchart LR
  Range[Original byte range] --> Header[Size, signed marker and base]
  Header --> Digits[Checked arbitrary-width digit accumulation]
  Digits --> Literal[Exact binary vector or contextual fill]
```

## Contracts and Invariants

Base letters are case-insensitive; s/S alone controls signed based literals.
Ordinary unsized decimal is signed, at least 32 bits, with enough bits for its
positive value and sign. Unsized based values are at least 32 bits and preserve
explicit signing. Sized values truncate high bits modulo 2^declaredWidth and
zero-pad absent high digits; marking a sized literal signed does not sign-extend
its source digits before sizing. The expression layer subsequently applies
signed extension from the resolved literal width. Size is positive and checked
against Int overflow and the context bit-width limit. '-' is a unary expression.
Digit separators follow a first digit; whitespace can separate size, base and
value, not individual digits or apostrophe/sign/base. Invalid syntax and X/Z
admission failures preserve the exact artifact/range; neither returns zero.

## State, Ownership, and Lifecycle

Temporary accumulation owns fixed-capacity UInt64 limbs. Final packed vector
owns exact-width planes. Source bytes remain borrowed; no spelling String or
intermediate digit array is materialized.

## Failure, Concurrency, and Constraints

Checked digit-derived temporary capacity and final planes reserve logical bytes
before allocation. Their overlap is charged; temporary reservation releases on
every exit. Per-digit/limb work and final bit width use the cumulative context.
All targets use the same immutable owners and local mutable workspace.

## Verification and Change Impact

Literal tests compare exact bits for values beyond 64 bits, signed markers,
unsized widths, truncation, separators and contextual fills; invalid digits,
X/Z, overflow, budget and cancellation must fail. Portable probes execute decoding.
Resolved elaboration tests own assignment-context sizing and arithmetic meaning.
