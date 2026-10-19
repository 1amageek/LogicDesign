# TechnologyLibrary

## Purpose and Scope

Own portable immutable technology-cell definitions and exact library membership.
Parent: [LogicIR](../DESIGN.md). No children. Boolean syntax is already normalized
by [CellFunctions](../CellFunctions/DESIGN.md); host Liberty compilation and mapped
connectivity are separate responsibilities.

## Responsibilities and Boundaries

Own canonical cell/pin identities, dense pin/cell indices, pin direction and output
function binding, explicit single-bit sequential definitions and finite area.
Own no Liberty parser, file access, digest computation, timing or power estimates,
cross-view discovery, cell selection, simulation scheduler or proof authority.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicIR](../DESIGN.md) | parent | Portable immutable values | Domain meaning | No host dependency |
| [CellFunctions](../CellFunctions/DESIGN.md) | depends on | Validated Boolean DAG | Actual pin/state function | No inferred node kind |
| [ExecutionControl](../../LogicKernelCore/ExecutionControl/DESIGN.md) | depends on | Cumulative budget/control | Admission before allocation | Callers keep the same context |
| [LibertyCodec](../../../../TimingEngine/Sources/TimingCore/LibertyCodec/DESIGN.md) | used by | Source facts consumed by future host compiler | Single grammar owner | Facts alone grant no library eligibility |

## Architecture

```text
validated Boolean functions + explicit pin/state bindings
  -> consuming cell builder -> immutable LogicTechnologyCell
  -> consuming library builder -> immutable LogicTechnologyLibrary
  -> mapper / mapped validator / simulation / CNF
```

## Contracts and Invariants

Each cell has a unique nonempty display name, canonical nonzero entity ID,
nonempty uniquely named/identified pins, at least one output and finite nonnegative
area. Input pins have no output function; every output pin has one. No missing
function becomes an inferred buffer, constant or gate. Every function declares
exactly `pinCount + stateCount` input slots. Slots below pinCount may reference
only physical input pins. A sequential cell has one state slot at pinCount;
combinational cells have none. Output references to other output pins are refused.
Unused physical input slots are valid, including constants and shared namespaces.

Sequential cells declare one FF edge or one latch gate polarity, one Boolean
next/data function and optionally one asynchronous clear/preset pin with exact
polarity and binary reset value. Clock/gate/reset pins must be physical inputs;
reset cannot alias the clock/gate. Sync reset/enable are explicitly included in the
next/data Boolean function. No async function is replaced by data-path multiplexing.
The profile has one internal state bit: a host compiler expands an inverted-state
symbol into explicit inversion. Dual controls, simultaneous clear/preset behavior,
banks, state tables, tri-state/X-function extensions and unbound source symbols
require an explicit host eligibility refusal, not an approximate cell.

Sequential definitions do not claim a power-up value. A clear/preset function
defines behavior when its physical input is asserted, not an initial input
constraint or startup guarantee. Callers cannot use mapped initial metadata or a
generic Verilog initial statement to manufacture such a guarantee. Actual startup
admission belongs to [MappedGraph](../MappedGraph/DESIGN.md); a future realized
startup mechanism requires exact target/cell semantics and independent consumer
execution before that contract can accept it.

The library retains its caller-supplied exact source ArtifactID and validated
cells. The host must establish this identity from verified source bytes; the
portable owner performs no hashing or artifact I/O. Cell IDs/names and all cell/pin
entity IDs are unique across the library. Dense indices follow admission order
and are distinct from canonical IDs. Display-name/ID changes do not alter function
slots; reordering pins requires explicit corresponding slot rebinding.

## State, Ownership, and Lifecycle

Both builders are `~Copyable`; consuming finish is the only publication path.
Published structs share immutable final storage; only scoped Span borrows expose
pin/cell tables. Functions retain their immutable owners. Names are cold metadata,
never evaluator lookup keys. All mutation and temporary membership indexes are
invocation-local. Every target uses the same storage and Sendable contracts.

## Failure, Concurrency, and Constraints

Callers supply positive capacities for pins/cells and a nonnegative total-pin
capacity. Checked concrete-stride arithmetic precedes array/Set reservation.
Name bytes, cell/pin storage and membership-index payload consume the run budget;
allocator headers/bucket overhead/RSS remain excluded. Operations check control and
charge work before scans and mutation. Publication validates every actual function
reference, including its state/data function. Width/model/resource/cancel/deadline
errors publish no owner. Failed builder operations do not append partial cells/pins;
prior work/admission remains consumed. Input functions are validated immutable
values; their initial construction budget belongs to the same composing context.
Reservations conservatively remain charged for the invocation after builder
membership indexes are destroyed; this is bounded admission, not an allocator or
peak-RSS measurement. Library validation and membership insertion work are both
admitted before any membership mutation.

| State | Native / WASM / Embedded storage | Isolation | Read / mutation | Release |
|---|---|---|---|---|
| Published cell/library | Same immutable final storage and Sendable values | Immutable | Checked index / scoped Span; no mutation | Last value owner |
| Cell/library construction | Same noncopyable builder with private arrays/sets | Exclusive invocation | Borrow / mutating append / consuming finish | Consume or scope end |
| Probe scratch | Same invocation-local context and builders | Exclusive invocation | Local calls | Function return |

There is no shared mutable state, callback, shutdown transition or conditional
Sendable/isolation branch in this component.

## Verification and Change Impact

`TechnologyLibraryTests` owns correct scalar combinational/FF/latch binding,
NAND and inverted-state functions, constants/multiple outputs, invalid direction,
wrong function arity, output-pin reference, control/reset polarity, duplicate
identities, nonfinite area, admission and cancellation behavior. Portable probes
exercise accepted/rejected owner construction on all three targets. Actual mapped
events and source/bit equivalence are separate simulation/proof completion gates.
