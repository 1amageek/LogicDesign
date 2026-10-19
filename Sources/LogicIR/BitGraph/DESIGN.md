# BitGraph

## Purpose and Scope

Validated two-state, technology-neutral bit circuits. Parent: [LogicIR](../DESIGN.md).
No child components. Word elaboration and cell mapping are separate owners.

## Responsibilities and Boundaries

Own dense node/state references, flat operands and port-bit bindings, explicit
sequential controls, admission and topology. Canonical `DesignEntityID` identifies
entities; dense indices address this particular design only. Source origins are
exact artifact byte ranges and never determine the operation.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicIR](../DESIGN.md) | parent | portable values | circuit representation | no host codec dependency |
| [ExecutionControl](../../LogicKernelCore/ExecutionControl/DESIGN.md) | depends on | cumulative budgets and checkpoint | run control | preserve one context across stages |
| [GraphConnectivity](../GraphConnectivity/DESIGN.md) | depends on | dense topological order | shared connection traversal | all controls and indices admitted first |
| [LogicValues](../LogicValues/DESIGN.md) | coordinates with | binary and four-state distinction | simulation values | bit circuit constants are binary |

## Architecture

```mermaid
flowchart LR
  Builder[Noncopyable fixed-capacity builder] --> Validate[Admission and connectivity topology]
  Validate --> Owner[Immutable table owner]
  Owner --> Borrow[Scoped Span borrowing]
  Validate --> Failure[Typed failure]
```

## Contracts and Invariants

`BitLogicDesign` publishes only through a consuming builder finish. Each node
produces one bit. Flat operand ranges are disjoint, contiguous and match opcode
arity. References may point forward; evaluation order is derived from connectivity.
Node, port and state IDs are unique within their entity table. Input ports bind
every input exactly once; output ports may observe the same value. Ports are
nonempty, little-endian ordered bit bindings. Inout ports are unsupported.

Each state has exactly one state-output node and one next-state bit. A design has
no state, only flip-flops, or only latches. All flip-flops share one clock value and edge; all latches share one gate value and polarity.
Reset dominates enable/data. Reset has explicit polarity, binary value and
synchronous/asynchronous kind. Latch resets must be asynchronous. Flip-flop outputs
break combinational paths. Latch admission adds transparent next-data/gate/reset
edges and rejects their cycles. No mixed state profiles, multiple drivers or inferred initial zero. An absent initial value admits both bits.

## State, Ownership, and Lifecycle

Builders own mutable arrays; published tables reside in an immutable final class.
Borrowing retains concrete storage and local arrays for the entire callback. Span
cannot escape or cross suspension. Borrow APIs require macOS 26 on Darwin; all
supported WASM SDKs must compile, link and execute the same source.
Borrow callbacks and their public entrypoints preserve the same generic typed
failure, including Void-returning callbacks. No error erasure or conversion occurs.

## Failure, Concurrency, and Constraints

The caller supplies capacities and a run context; no operational maxima are built
in. Capacity arithmetic is overflow-checked. Before allocation, reserve all table
capacity bytes, validation workspace and charge entity/edge/work budgets. Published
storage and builder capacity remain conservatively charged for the invocation.
Temporary validation arrays release their reservation on both success and failure.
Managed table counts exclude allocator overhead and process RSS, as defined by
ExecutionControl. The builder never grows beyond admitted capacities. Rejected
finish publishes no design. Context exhaustion/cancellation propagates unchanged.
Immutable designs are Sendable; builders are invocation-local and noncopyable.

## Verification and Change Impact

[BitGraphTests](../../../Tests/LogicDesignTests/BitGraphTests.swift) owns invalid
references/arity, forward-reference topology, port/state coverage, mixed profiles,
reset restrictions, transparent cycles, capacities and cancellation. Portable
probes execute the actual builder/borrow path on all three targets. Downstream
lowering, simulation, optimization and proof must use validated owners rather than
legacy mutable draft models.


| State | Native | WASM | Embedded WASM | Read / mutation / release |
|---|---|---|---|---|
| Published graph | immutable Storage | same | same | scoped borrow / none / ARC owner lifetime |
| Builder | invocation-local noncopyable arrays | same | same | builder methods / mutating methods / consuming finish or destruction |
| Validation workspace | invocation-local arrays | same | same | validation / local mutation / release on success or failure |
| Cancellation | LogicKernelCore Mutex owner | same | same | protocol checkpoint / owner cancel / owner lifetime |

No target branch changes storage or Sendable. WASI executions are sequential and
do not establish multi-threaded WASI lock semantics. Native tests separately
exercise concurrent immutable value readers and cancellation. Empty tables use
`Span()` on every target, avoiding the fixed SDK's empty Array alignment trap.
