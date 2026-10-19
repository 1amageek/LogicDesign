# MappedGraph

## Purpose and Scope

Own the immutable actual-cell netlist, distinct from WordGraph and BitGraph.
Parent: [LogicIR](../DESIGN.md). No children. Host library compilation, mapping,
simulation and CNF construction consume this contract but are separate owners.

## Responsibilities and Boundaries

Bind each instance to a dense cell index in a retained immutable technology
library, each physical pin to one scalar net, and each sequential instance to one
canonical state identity. Own net-driver validation, flattened port/pin tables,
single control profile and connection-derived evaluation order. Own no parser,
cell selection, timing estimate, event scheduler, hash computation or proof.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicIR](../DESIGN.md) | parent | Portable stage values | Representation boundary | Mapped values are not BitLogicDesign |
| [TechnologyLibrary](../TechnologyLibrary/DESIGN.md) | depends on | Immutable validated cells | Actual functions and physical controls | Never infer functions from origin/opcode |
| [GraphConnectivity](../GraphConnectivity/DESIGN.md) | depends on | Cycle-refusing topology | Evaluation from connectivity | No identifier/name sorting |
| [ExecutionControl](../../LogicKernelCore/ExecutionControl/DESIGN.md) | depends on | Cumulative resources/control | Admission and work | Same composing context |

## Architecture

```text
exact validated library + scalar nets + flat instance pins + flat port bits
  -> exclusive consuming builder -> binding/profile/topology validation
  -> immutable MappedGateDesign retaining that library
  -> actual-cell simulation / miter / standard host export
```

## Contracts and Invariants

Every net has exactly one explicit driver: primary input, binary constant or exact
instance/output-pin pair. Every physical instance pin has exactly one net. Each
output connection must point back to that same driver pair, so two outputs cannot
share a driver net. Unused outputs still have explicit nets. Input ports bind each
primary input exactly once; output ports may alias driven nets. Ports have positive
width. All dense indices/ranges are checked before publication. Nets, instances,
ports and state identities are distinct within this design; library identities
belong to their separate exact library namespace. Scalar nets need no word-width
inference. Port bit order is explicit.

Sequential instance state identity is present exactly when the cell has a state
definition. Initial state is an explicit binary value or unspecified (simulation X;
two-state proof permits both binary initial values). No implicit zero is inserted.
An explicit initial value is an abstract-model demand, not evidence of physical
power-up behavior. Current TechnologyLibrary cells describe transitions and
reset controls, not a power-up mechanism. `MappedGateRealizationValidating` checks
the independently selected realization policy without changing the graph:
`standardNetlist` refuses specified sequential initial values and permits logical
binary constant drivers; `physicalCells` additionally requires every constant
driver to be replaced by an actual constant-function cell before admission.
An asynchronous reset pin does not establish reset assertion at startup.
Source defaults and initializers remain intact in RTL, word/bit graphs and abstract
mapped models; unsupported physical startup is never changed to unspecified.
All FFs share one logical clock and effective edge. After driver, pin, port and
DAG validation, `withStateClocks` exposes immutable `MappedStateClock` entries in
sequential-instance declaration order. Each retains the physical `carrier`, local
`risingEdge`, instance index, and derived `MappedClockLineage`: either
`primaryInput(root:inverted:risingEdge:)` or `opaque(carrier:risingEdge:)`.
For a primary lineage, carrier = root XOR inverted and the effective root edge is
local risingEdge XOR inverted. State-free actual output functions qualify only
when their reachable cone references exactly one physical input slot and its two
Boolean evaluations are identity or inversion. Dead nodes and unused pins do not
contribute. Cell names, origins and serialized metadata confer no authority.
Fanout and arbitrary-depth identity/inverter chains retain the actual netlist.
Different physical FF carriers are admitted only when both lineages have the same
primary-input root and effective edge. Constant, gated, generated/state-derived,
or multi-input carriers do not qualify for this relaxation. Existing same-raw-
carrier, same-local-edge admission remains valid, including opaque controls.
All latches still share one raw gate net and polarity; mixed FF/latch is refused.
No BitGraph single-control contract changes. Decode rederives lineage through the
same builder and never serializes or trusts the derived table. Controls and reset
meaning come from actual cell pins, never historical RTL operation metadata.

Evaluation vertices comprise scalar nets and explicit state vertices. Dependencies
use only each Boolean function's reachable output cone, including its actual pin
and state slots. FF state vertices break data feedback. Latch state vertices depend
on data, gate and asynchronous reset, so transparent feedback is rejected. Dead
Boolean nodes and unused physical inputs do not invent dependencies. Functional
output functions may depend on both inputs and state. A connection-derived DAG
order is published; identifiers and display names never determine depth/order.

The design retains the exact library owner used during validation. A separately
supplied library must have the same source ArtifactID and exact ordered cell/pin,
state, area and Boolean definitions. A copied owner passes immediately; an
independently rebuilt identical owner passes a budgeted exact comparison. Reusing
only an ArtifactID with changed functions is rejected. The host still verifies
the source identity against source bytes; portable code performs no hashing.

## State, Ownership, and Lifecycle

Builder is noncopyable and invocation-local. Publication consumes it into immutable
final storage. Scalar tables, pins, ports and evaluation order are available only
through checked access or scoped Span borrows retaining their owners. Origin
ranges remain metadata on nets/instances and do not replace functions.

| State | Native / WASM / Embedded storage | Isolation | Mutation / release |
|---|---|---|---|
| Published design/library | Same immutable Sendable owners | Immutable | No mutation; last owner release |
| Construction/validation | Same exclusive builder and temporary arrays/sets | Run-local | inout / consume / scope exit |

No shared mutable state, conditional conformance, callback or shutdown is added.
Realization validation borrows the same immutable tables on every target, owns no
state or allocation, and charges cumulative work/checkpoints before each examined
instance/net. Host export, whose existing byte API has no kernel context, applies
the same per-instance startup requirement before emitting any bytes. Scoped views
remain synchronous and cannot escape their retained design owner.

## Failure, Concurrency, and Constraints

Caller capacities are nonnegative and overflow-checked before concrete-stride
reservation. Construction retains admitted payload for the invocation; validation
temporaries have scoped receipts released on success and failure. Allocator
metadata and RSS are outside managed-payload accounting. Node/edge/state/work and
width budgets are cumulative, and all scans perform run-control checkpoints.
Clock derivation uses the validated connection order, a dense per-net memo table
and reusable per-function reachability/two-assignment scratch; no recursive trace
or hash-budget guess is needed. Persistent clock entries are reserved with builder
capacity; all temporary payload, scans and operations use the same cumulative
context, checked arithmetic and run-control checkpoints. Temporary reservations
release on success and failure. Capacity/model/control/resource/cancellation failures publish no design. Failed
append does not append partial tables; earlier admission/work stays consumed.

## Verification and Change Impact

`MappedGraphTests` owns wrong pins/drivers/library definitions, reverse declaration
order, output-cone dependencies, cycles, FF feedback, latch transparency, control
profile, initial state/origin, capacities and cancellation. Portable probes verify
accepted and rejected mapped construction on Native/WASM/Embedded. Event behavior,
proof and serialization round-trip are subsequent consumer-owned gates. Changes
to TechnologyLibrary or graph topology require these binding regressions; changes
to this contract require mapper/simulation/proof consumers to recheck assumptions.

Realization regressions cover initialized FF/latch refusal, unspecified state
admission, unchanged abstract initial values, logical-constant policy separation,
actual tie-cell acceptance, cancellation and cumulative work limits. Shared
portable probes execute those same requirements on Native/WASM/Embedded.
LogicEngine mapping owns optional physical-cell realization of constants before
proof/receipt publication; PhysicalDesignEngine owns exact physical master/pin
admission. Neither physical insertion nor a supply-net alias may silently change
the checked mapped graph. LogicEngine must apply the selected policy on synthesis
and receipt reload after adopting this lower contract.

Clock-lineage regressions own independent BUF branches, long chains, even/odd
inversion and edge compensation, different roots/edges, false cell-name hints,
reachable multiple inputs, constants/generated controls, opaque legacy admission,
cycles, malformed drivers, decode rederivation and resource/control failure.
Native/WASM/Embedded probes exercise the same derived owner and borrowing path.
This admission does not establish proof normalization, per-state event history,
CTS timing, physical realization or equivalence; those consumers adopt separately.
