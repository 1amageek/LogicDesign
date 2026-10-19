# Dataflow

## Purpose and Scope

Canonical external-independent SSA/process/channel values and validation. Parent: [LogicIR](../DESIGN.md). No children.

## Responsibilities and Boundaries

Own the responsibility identified in Purpose and Scope. Public assumptions and
guarantees are defined once in Contracts and Invariants below.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicIR](../DESIGN.md) | parent | composition and ownership | containing design | preserve dependency direction |

## Architecture

```mermaid
flowchart LR
  Caller --> ValuesAndValidation
  ValuesAndValidation --> Core[portable dependency floor]
```

## Contracts and Invariants

Canonical external-independent SSA/process/channel values and validation. Host coding and content hashes are outside this component. Public draft values do not assert stage-specific synthesis validity.

## Verification and Change Impact

[LogicDesignTests](../../../Tests/LogicDesignTests) own behavioral checks for this component. Changing value meaning requires host serialization and consuming kernel regression checks.
