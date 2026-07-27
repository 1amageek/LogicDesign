# LogicDesign Remaining Tasks

Updated: 2026-07-26

LogicDesign is complete for its declared native SystemVerilog, power-intent,
RTL/gate, and dataflow/process canonical IR subsets.

## Remaining tasks

| ID | Priority | Owner | Task | Exit criteria |
|---|---|---|---|---|
| LD-1 | P2 | LogicDesign | Expand SystemVerilog, UPF, and CPF semantics beyond the declared native subset when platform requirements demand them. | Each added semantic has canonical IR behavior, deterministic serialization, typed negative diagnostics, retained fixtures, CLI coverage, and oracle correlation where an independent oracle exists. |
| LD-2 | P2 | LogicDesign | Expand canonical dataflow operation semantics when native engines or interoperability requirements demand them. | Each operation has external-independent type rules, validator coverage, deterministic serialization, and success/failure fixtures. |

## External prerequisites

Process qualification, Xcircuite execution, downstream signoff, and release
authorization remain consumer responsibilities.

## Evidence reviewed

- `README.md`
- `DESIGN.md`
- `INTERFACES.md`
- `IMPLEMENTATION_PLAN.md`
- `MILESTONES.md`
- `GOAL_STATUS.md`
- `Sources` incomplete-implementation marker scan
