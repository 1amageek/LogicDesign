# ConstantEvaluation

## Purpose and Scope

Evaluate synthesis-profile integral parameter defaults after module-local binding.
Parent: [SystemVerilogFrontend](../DESIGN.md). No children. This is not a complete
frontend or hierarchy elaborator.

## Responsibilities and Boundaries

Own self/context-determined expression width and sign, integral constant values,
packed dimension ordering and source-located constant admission. Consume existing
binary arithmetic; do not implement a second limb backend. Binding owns module-default identity. [StaticScopes](../StaticScopes/DESIGN.md) owns
selected lexical declarations; later hierarchy elaboration owns selection/unrolling.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Frontend](../DESIGN.md) | parent | composition | synchronous stages | not whole-module acceptance |
| [Binding](../ParameterBinding/DESIGN.md) | depends on | exact declaration references | ordered defaults | names are not reinterpreted |
| [Values](../../LogicIR/LogicValues/DESIGN.md) | depends on | arbitrary-width binary operations | arithmetic authority | X/Z rejected for synthesis |
| [ExecutionControl](../../LogicKernelCore/ExecutionControl/DESIGN.md) | depends on | cumulative budget/control | bounded evaluation | no reset between stages |

## Architecture

```mermaid
flowchart LR
  Bindings --> Decl[Earlier parameter values]
  Decl --> Type[Self-determined expression types]
  Type --> Context[Assignment and operand context propagation]
  Context --> Value[Binary evaluation]
  Value --> Defaults[Immutable typed parameter defaults]
```

## Contracts and Invariants

Defaults are evaluated in bound declaration order. Explicit types/ranges fix
assignment width; sign-only implicit types inherit initializer width except
unsized literal defaults, which use 32 bits. Fully implicit integral parameters
infer a flat vector with the initializer sign/width, with unsized literal
defaults widened to at least 32 bits. Only literal syntax has the unsized flag;
unary/binary/cast expressions have their computed type. Integer atoms are 32-bit
signed unless unsigned.
An assignment context widens arithmetic before computation and truncates only
at assignment. Destination signedness does not make an unsigned RHS signed.
Mixed signed/unsigned binary operands use unsigned common context. Comparisons
and logical/reduction operations produce one bit. Shift amounts, concatenation
operands, selection indices and signed casts are self determined; a cast changes
sign after evaluating its operand. Conditional branches use common result width
and sign. All syntax operands are type-admitted, even when not value-selected.

Packed dimensions retain declaration direction and index bounds. Selections
remove/select the leading packed dimension, preserving remaining dimensions.
Part-select direction and indexed-select positive width are checked. A selected
out-of-range bit would be X and therefore fails synthesis admission. Constant
X/Z and indefinite-width concatenation operands fail with exact source identity.
Overflow in widths/ranges/counts fails explicitly, before allocating results.
Zero repetitions are an explicit empty intermediate permitted only within a
nonempty concatenation; no dummy bit vector or standalone zero-width parameter
is published.

Overrides retain an unevaluated expression and its parent parameter-default owner.
Identifiers resolve in that parent scope; declared parameter types and ranges resolve
in the child scope using previously evaluated child overrides. Explicit child widths
propagate into parent arithmetic before computing the value. Implicit child types
infer from the override expression, not the replaced default. An overridden default
is name-bound but not evaluated, since its dimensions may become invalid under
other overrides. Duplicate targets, localparam or implicitly local body-parameter targets and foreign binding owners
fail before publication. Published parameter values retain the exact initializer source range, including the
parent override expression. The retained binding owner separately identifies the
child declaration and type syntax. All supplied expressions are checked as synthesis constants
with exact source locations. Matching named/ordered instance assignments is owned
by hierarchy composition, not by this evaluator.

## State, Ownership, and Lifecycle

A noncopyable run-local evaluator owns flat metadata, explicit traversal stacks
and prior parameter values. Immutable final Sendable storage retains bindings
and published values. Typed tables are borrowed through scoped Span closures.
No shared mutable state, recursive ownership or recursive expression traversal.
An immutable constant-expression handle retains its parent defaults and source;
reusable evaluation uses a fresh noncopyable workspace, sharing only immutable
parameter values. An override lookup table is allocated only for supplied overrides
and charged by the actual target stride. Expression scratch releases on every exit.

## Failure, Concurrency, and Constraints

Node-count-bounded tables/stacks are admitted by actual target type strides
before allocation. Dimension payload and every new value plane are charged.
Work/expansion and run control are checked while traversing, selecting and
repeating. Scratch releases on all exits; retained publication/value charges
remain conservative for the invocation. Managed storage excludes allocator
metadata/RSS. Source failures preserve their original artifact and byte range.

## Verification and Change Impact

[ConstantEvaluationTests](../../../Tests/LogicDesignTests/ConstantEvaluationTests.swift)
owns context-before-arithmetic, signedness, unbased
fills, wide values, packed directions/selects, repetition, source rejection,
budget/cancellation and owner retention. Shared probes execute the same stages
on Native/WASM/Embedded. Later frontend/lowering must consume these rules;
passing constant tests does not establish process or mapped-cell semantics.
The language reference is IEEE 1800-2023; primary cross-checks include
[slang parameter tests](https://github.com/MikePopoloski/slang/blob/master/tests/unittests/ast/ParameterTests.cpp).

[ParameterOverrideTests](../../../Tests/LogicDesignTests/ParameterOverrideTests.swift)
owns parent/child scope isolation, context-sensitive carry, dependent child ranges,
inferred replacement types, localparam/duplicate/foreign target refusal, unknown
parent names, budget/cancel and retained owners. Shared runtime probes cover the
same contextual override path on all three targets. These contracts do not prove
instance matching or complete hierarchy elaboration.

Scoped expression handles retain their exact lexical owner. Identifier lookup uses
nearest scoped declarations, including nonconstant blockers and pending localparams;
module defaults keep their original bound declaration authority. Local declaration
evaluation reuses this component's type/context rules and publishes through the
scope owner, without mutating/copying the dense module-default value table.

The module-default expression overload validates direct module ownership through
StaticScopes before type inference. Nested expressions require their lexical scope;
a broad enclosing module byte range is insufficient authority to resolve names.

StaticControl consumes an explicit common-signedness expression operation for
case-wide and compound-assignment contexts. Ordinary assignment/override evaluation
continues to use RHS signedness; a destination's sign never changes it implicitly.

Runtime expression inference consumes exact immutable signal bindings from
[ExpressionResolution](../ExpressionResolution/DESIGN.md) and shares the same
integral sizing algorithm. Runtime-dependent facts are type-only; constant value
evaluation refuses them at source. Dynamic selection metadata records mathematical
normalization facts without fabricating constant index values.

Writable-target inference marks only identifier/selection/concatenation paths.
Index expressions retain ordinary read admission. Writable indexed selections
retain exact normalization even for constant or out-of-range indexes; fixed
part-selects retain signed offsets. This permits the program owner to discard
invalid destinations without inventing X data or admitting out-of-range reads.

Language-constant contexts validate declaration roles independently of known
values. A frozen procedural variable remains a variable in parameter defaults,
type bounds, fixed selection bounds, indexed widths and repetition counts.
Implicit generated localparams retain constant legality.
