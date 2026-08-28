# 0012 — Two roasters: Primo as baseline, Probat added alongside

- **Status**: Accepted
- **Date**: 2026-08-27

## Context

Until now the portal assumed one roaster. `green_coffee_settings` carried a single
`batch_size_lbs` and `shrinkage_pct` per coffee, and `renderRoasting()` ignored the
shrink column entirely — it multiplied roasted lbs by a hardcoded `SHRINKAGE = 1.176`
for every coffee. The stored `shrinkage_pct` was editable in the UI but had no effect
on any number the roaster saw.

Torque now runs a second roaster, the Probat, with a much larger drum. Batch size and
shrink differ per coffee *and* per machine, so a single pair of columns can no longer
describe the plan. The roaster needs to see, per row, which machine a coffee is on and
what that implies for batch count, plus a split of total batches by machine.

The V2 redesign also required the shrink figure to actually drive the math, since the
per-machine editors would otherwise be decorative.

## Options considered

- **Rename to `primo_*` and add `probat_*`** — symmetrical column names, but renames
  columns that working code and a live production tool already read.
- **Separate `machine_settings` table keyed (coffee, machine)** — cleanest normal form,
  but a join and a migration of live data for two machines that are unlikely to become five.
- **Keep the existing columns as the Primo values and add Probat alongside** — asymmetric
  names, no rename, no data movement.
- **Store machine choice per plan-date on `roasting_progress`** — resets daily, which is
  wrong: which roaster a coffee runs on is a property of the coffee, not of today.

## Decision

Keep `batch_size_lbs` / `shrinkage_pct` as the **Primo** values and add three columns:
`probat_batch_lbs` (nullable), `probat_shrink_pct` (default 15), and `roast_machine`
(default `'primo'`, checked against `primo|probat`). Machine choice is a persistent
property of the coffee.

`probat_batch_lbs` is deliberately nullable. An unset Probat batch size makes the row
show a red "Set Probat batch size" prompt and display `—` for the batch count, rather
than computing a number from a guessed default.

Green lbs is now `roasted / (1 - shrink/100)` using the selected machine's shrink.

## Consequences

**Positive:** Purely additive migration — nothing renamed, no existing value changed.
All 25 coffees were at `shrinkage_pct = 15` at cutover, and `1/0.85 = 1.17647` matches
the old `1.176` constant, so no displayed Primo number moved. The stored shrink column
finally means something.

**Negative:** Column names are asymmetric — `batch_size_lbs` means "Primo batch size"
and only a column comment says so. A third roaster would force the normalised table
this decision declined to build.

**When to revisit:** A third machine, or a coffee that needs to be split across both
roasters on the same day (the current model allows exactly one machine per coffee).
