# CellFunctions

## Purpose and Scope

Own technology-cell Boolean function representation and validated publication.
Parent: [LogicIR](../DESIGN.md). No children. This value contract is shared by
Liberty normalization, mapped simulation, technology mapping and symbolic proof.

## Responsibilities and Boundaries

Own flat Boolean operations, dense node references, input-slot arity and immutable
function storage. Source grammar, terminal names, pin directions, state control,
library identity, evaluation workspace and SAT construction belong to consumers.
No function can be constructed by an unchecked public initializer or host decoder.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicIR](../DESIGN.md) | parent | Portable values | Meaning owner | No host dependency |
| [LogicValues](../LogicValues/DESIGN.md) | depends on | Boolean scalar truth tables | Value semantics | Two-state proof does not imply four-state equivalence |
| [ExecutionControl](../../LogicKernelCore/ExecutionControl/DESIGN.md) | depends on | Cumulative admission | Bounded construction | Same context continues through consumers |
| [LibertyCodec](../../../../TimingEngine/Sources/TimingCore/LibertyCodec/DESIGN.md) | used by | Future source-to-function binding | Single grammar authority | Named source facts require exact pin/state binding |

## Architecture

```text
explicit input count + node capacity
  -> noncopyable builder -> checked topological operations -> consuming finish
  -> immutable function owner -> scoped Span borrow by evaluator / mapper / proof
```

## Contracts and Invariants

`LogicBooleanOperation` represents a Boolean constant, a dense input slot,
inversion, AND, OR or XOR. NAND/NOR are explicit inversion compositions. Operators
have no string interpretation, inferred source-node kind or hidden pin permutation.
Operations address earlier nodes only. The output must address one published node.
The builder checks input and node bounds before accounting or mutation; no forward
edge, cycle, negative slot or invalid output is published. Zero-input constants
are valid. Unused declared input slots are permitted for shared cell namespaces.
Node indices are dense references, never canonical entity IDs or display names.
Both operands are represented even when they address the same node.

Input and output are single-bit Boolean quantities. Simulation interprets the
same operations through LogicBit's four-state operator rules; SAT interprets their
two-state truth functions. The representation carries no don't-care assumption.
The function itself does not execute simulation or grant equivalence evidence.

## State, Ownership, and Lifecycle

The builder is `~Copyable` and publication consumes it. One immutable final storage
owner retains a transferred operation array. `withOperations` retains that owner
and array for the callback, preserving its typed failure; Span never escapes.
All mutable construction state is invocation-local, with no target branches or
shared mutable workspace. Consumers own any repeated-evaluation workspace.

## Failure, Concurrency, and Constraints

Callers supply positive node capacity and nonnegative input count. Checked stride
multiplication and owner-metadata addition precede reservation/allocation. Logical
capacity, nodes, edges and work consume the shared context; control is checked
also at publication. Failed mutation leaves the builder unchanged, though work
already performed remains consumed. Published payload remains charged until the
invocation ends. Resource/cancel/deadline failures never return a function.

## Verification and Change Impact

[CellFunctionTests](../../../Tests/LogicDesignTests/CellFunctionTests.swift) owns
actual validated construction and independent truth evaluation of AND/NAND/NOR,
inversion, pin permutation, XOR and constants; malformed edges/inputs/output,
capacities, budget and cancellation must fail. The portable probe exercises the
published operations on Native/WASM/Embedded through the same scoped borrow.
Changes affect later library admission, mapped simulation, mapping and CNF proof;
those composing paths require their own behavioral evidence before S3/S4 completion.
