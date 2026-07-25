# LogicDesign Remaining Tasks

Updated: 2026-07-26

LogicDesign is complete for its declared native SystemVerilog, power-intent, and
canonical IR subset.

## Remaining tasks

| ID | Priority | Owner | Task | Exit criteria |
|---|---|---|---|---|
| LD-1 | P2 | LogicDesign | Expand SystemVerilog, UPF, and CPF semantics beyond the declared native subset when platform requirements demand them. | Each added semantic has canonical IR behavior, deterministic serialization, typed negative diagnostics, retained fixtures, CLI coverage, and oracle correlation where an independent oracle exists. |

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
