# 0015 — "Lbs Needed" is a physical count, not a second roasting plan

- **Status**: Accepted
- **Date**: 2026-09-03

## Context

Before bagging starts, someone has to answer one question: *do we have enough
roasted coffee of each single origin to fill today's orders?* Until now the only
place to look was the Roasting tab, which does explode Drops into their component
single origins — but its numbers are built for the roaster, not the bagger, and
they answer a different question in three separate ways.

The operator's ask: one list, read down against the physical bins, judgment call
made, done. No editing, no locking, no counters.

## The three deliberate divergences from Roasting

`renderRoasting()` already computes a per-single-origin roll-up. Reusing it would
have been the smaller diff and the wrong answer:

1. **`qty_needed`, not `qtyRemaining`.** Roasting nets out what's already bagged,
   so its numbers shrink through the day. That is correct for a roaster deciding
   what still has to go in the drum, and wrong for a 7am inventory check — the
   figure you compared against the bins at 7am must still mean the same thing at
   7:30, or the comparison was worthless.
2. **Roasted lbs, stopping before the green conversion.** Roasting's output is
   green lbs and batch counts (`roasted / (1 - shrink/100)`, per ADR 0012). The
   bagger is holding roasted coffee. Applying shrink here would overstate every
   row by ~17.6%.
3. **Ignores plan state.** Roasting honors `roastLocks` freezes and excludes
   lines that arrived after `plan_state.finalized_at` (ADR 0013). Those are
   properties of *the plan*. Whether there are enough beans in the bin is a
   property of *the world*, and doesn't care whether the day was finalized.

## Decision

A separate `computeRoastedNeeded()`, not a parameterized shared function. The
two computations agree only on the blend-explosion step; forcing one function to
serve both would need three flags and would make each call site harder to read
than the twelve lines it saved. They are allowed to disagree, and the tab says
so on screen so nobody files the difference as a bug.

**xBloom is excluded entirely** — both the pod SKUs and the rare
`Cocoa Drops xBloom Bulk 40lb Box`. It is planned separately and is not filled
off the daily bagging list. Detection is `/xbloom|xpod/i` against product name
*and* variant title. Exclusion is **per line, not per product**: a coffee with
both an xPod variant and ordinary 12oz bags keeps its bag lines. The on-screen
"not counted" note lists the excluded *lines* and only those that carried real
weight, because naming the product would falsely imply its bags were dropped too.

**Blend ratios that don't total 100% raise a red banner on this tab**, not just
on Roasting. Every component number below a broken blend is wrong, and this is
the list someone acts on.

## Tab bar

Adding a ninth tab would have wrapped the row onto a second line on the iPad, so
**Help moved out of `.tabs` into the header beside Activity**, styled as
`.activity-btn` — the two rules were already visually identical, so this cost no
new CSS beyond an active state. The tab row stays at nine and on one line.

Two callers looked the Blends button up **by position** —
`document.querySelectorAll('.tab')[3]` in the blend-issue banner and in
`gotoBatchSizes()`. Inserting a tab before Blends would have silently sent both
to B2B with no error. Every tab now carries `data-tab`, and a `gotoTab(name)`
helper does the lookup by name.

## Consequences

**Positive:** The Bagging-time question has an answer that doesn't move.
Read-only, so it cannot corrupt the plan. No schema change, no new Supabase call
— it renders off `planData` and `blendMatrix`, already in memory. Position-based
tab lookups are gone.

**Negative:** Two functions now explode blends, and a change to `blend_matrix`
semantics has to be made in both. The tab shows a number that legitimately
differs from Roasting's for the same coffee, which will be reported as a bug at
least once — hence the subhead.

**When to revisit:** if the team wants to record the counted on-hand figure and
see the shortfall computed, this stops being read-only and needs a table. That is
a different feature and should not be bolted on quietly.
