# LogicValues

## Purpose and Scope

Arbitrary-width packed digital values. Parent: [LogicIR](../DESIGN.md). No children.

## Responsibilities and Boundaries

Own positive bit widths, packed four-state encoding and safe scoped bit-plane
borrows. Own no language parsing, simulation scheduling, host coding or digest.
Binary value methods own fixed-width modular arithmetic and packed value
transformations. Callers resolve language sizing/signedness before calling them.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicIR](../DESIGN.md) | parent | portable value contract | shared circuit meaning | no host dependencies |
| [ExecutionControl](../../LogicKernelCore/ExecutionControl/DESIGN.md) | depends on | width and storage accounting | bounded materialization | retain reservations through invocation |

## Architecture

```mermaid
flowchart LR
  Width[validated LogicBitWidth] --> Vector[immutable vector owner]
  Vector --> Borrow[scoped Span bit planes]
```

## Contracts and Invariants

Bits are little-endian UInt64 words. Both planes have exactly ceil(width/64)
words and unused tail bits are zero. Encoding (unknown,value) is 00=0, 01=1,
10=X, 11=Z. X/Z are never optimization don't-care values. Construction from
caller-owned words validates without materializing an intermediate array.
Repeated-value construction accounts allocation before allocating. Published
storage is immutable and Sendable; a Span never owns or outlives its storage.
The generic typed-throws plane borrow preserves the callback's exact failure type.

Binary arithmetic rejects X/Z instead of silently converting them.
Every binary input and generated result observes the invocation's bit-width limit,
including identity transforms that retain an existing owner. Add, subtract,
negate and multiply return modulo 2^width, with equal operand widths required.
Bitwise operations preserve that width. Resizing explicitly selects zero or sign
extension and permits truncation. Comparisons explicitly select signedness.
Shifts interpret the amount as an arbitrary-width unsigned bit pattern; amounts
at least the value width produce zero or the requested arithmetic sign fill.
Concatenation places the receiver above the argument; slicing requires an in-range
static interval. Binary reduction returns a Boolean. Checked conversion to Int is
only for bounded host/target table indices and rejects unrepresentable values;
Int is never used as the circuit-value domain.

Four-state operations are separate methods and never weaken binary admission.
Callers resolve operand sizing and signedness; binary bitwise, arithmetic, equality
and relational operations require equal widths. Logical conversion is zero for an
all-zero value, one if any known bit is one, otherwise X. Bitwise/reduction operators
use controlling zero/one and normalize participating Z to X. Logical equality is
zero for any known mismatch, X for an otherwise ambiguous comparison; case equality
compares both planes exactly. Relational and arithmetic results become X if any
operand contains X/Z. Arithmetic otherwise uses the checked modular binary kernel.
Conditional selection returns the chosen operand for a known predicate; an unknown
predicate merges corresponding bits, retaining identical known bits and producing
X otherwise (including Z paired with Z). Structural resize/slice/concatenation and known-distance shifts
preserve both planes, including Z; arithmetic right shift replicates the exact
sign bit. An X/Z shift distance produces an all-X result. Shift distance never
converts an arbitrary-width circuit value to a target Int before range checking.

Four-state operations borrow immutable input planes and allocate exactly two
admitted result planes through a scoped MutableSpan. Predicates/reductions return
LogicBit without a result allocation. Width checks and run-control checkpoints
also apply to identity/short-circuit paths. Every scan and result-word operation
charges work. Published result payload remains charged for the invocation; this
is not allocator/RSS/stack accounting or a measured zero-copy claim.

## State, Ownership, and Lifecycle

A value retains immutable backing storage. The consuming constructor transfers
array ownership; views retain the owner for the complete callback. Invocation
storage reservations cover generated values until the run ends. Allocator and
container overhead remain separately measured, not claimed as exact managed bytes.
Binary computations borrow input planes and mutate only a fresh result buffer
through a scoped MutableSpan. Result planes are admitted before allocation and
retained in the invocation budget. Same-width resizing can retain the original
immutable owner. Methods use no unsafe boundary or shared workspace.

## Verification and Change Impact

[LogicValuesTests](../../../Tests/LogicDesignTests/LogicValuesTests.swift) own tail,
word-count, bounds, 65/129-bit and 4-state checks. The shared portability probe
executes these constructors and scoped borrows on all three targets. Encoding
changes affect simulation, lowering, mapping, proof and host codecs.
[BinaryValueTests](../../../Tests/LogicDesignTests/BinaryValueTests.swift) compares
small-width results with independent integer arithmetic and covers multi-limb
carry/borrow/multiplication, signed tails, overshifts, checked indices, X/Z refusal,
storage and cancellation. Portable probes execute multi-limb arithmetic on all
three targets. These tests do not establish SystemVerilog expression sizing.

[FourStateValueTests](../../../Tests/LogicDesignTests/FourStateValueTests.swift)
owns independent truth-table enumeration, multi-limb X/Z-preserving transforms,
binary arithmetic agreement and refusal of width/storage/work/cancellation errors.
The portable probe runs the same production operations on Native, ordinary WASM
and Embedded WASM. Scheduling, process races, clock edges and cell selection remain
owned by their later simulation/library components.

The operator contract follows IEEE 1800-2023 clauses 11.4.3 through 11.4.12,
especially the ambiguous conditional table 11-20. The source is the
[IEEE standard](https://ieeexplore.ieee.org/document/10458102); the
[standard text mirror](https://studylib.net/doc/28213445/system-verilog-standard-1800-2023)
was checked against the corresponding 2017 clauses for these unchanged rules.
