# 0013 — Plan finalization, the roasting freeze, and an undoable activity log

- **Status**: Accepted
- **Date**: 2026-08-27

## Context

Three related gaps surfaced once the V2 roasting page was in use.

**Lock did nothing.** `roastLocks` was an in-memory object, and `renderRoasting()`
skipped locked coffees when building `coffeeNeeded` — so locking a row removed it
from the plan entirely, taking its own Unlock button with it. The intent was never
clear from the code. Andy's is: a locked row should be **frozen against new bagging
demand** while still counting toward the totals, because the roasting page *is* the
total that needs roasting.

**The day never closed.** Every Shopify pull rewrote today's numbers, including
after the roast was already set. There was no way to say "this is the plan" and no
record of orders that arrived too late to make it.

**Nothing recorded who did what.** On a shared iPad with several people tapping
counters, a wrong number had no history and no way back.

`daily_plan` had `updated_at` but no `created_at` — and `updated_at` moves on every
bagged increment, so nothing in the schema could answer "did this line arrive after
we finalized?".

## Options considered

- **Freeze the batch count** rather than the demand — simpler, but then editing a
  batch size or switching machine on a frozen row would do nothing, which reads as broken.
- **Freeze in memory only** — no migration, but a refresh silently unfreezes and the
  row starts tracking live demand again. Same class of bug as the one being fixed.
- **Derive "late" from `updated_at`** — no migration, but wrong the moment anyone taps `+`.
- **Delete activity rows on undo** — smaller table, but the log then lies about what happened.

## Decision

Freeze the **roasted-lbs demand**, persisted per coffee per day in
`roasting_progress.locked_roasted_lbs` (null = tracking live). Machine and shrink
edits still recalculate a frozen row — those are deliberate acts, not incoming demand.
A frozen coffee stays listed even if its live demand falls to zero, and counts in
every total.

Add `plan_state (team_id, plan_date, finalized_at)`. Finalizing stamps the moment;
lines whose `daily_plan.created_at` is later are shown in a separate "came in after
lock" section and excluded from the roast math, with an "Add to today anyway" escape
that backdates the line to just before the lock.

Add append-only `activity_log`, with an `undo` jsonb payload of
`{table, id, column, prev}`. Undo writes the previous value back and flags the row
`undone` rather than deleting it. Only counter changes carry a payload; order pulls,
finalization and label purchases are recorded but not undoable.

## Consequences

**Positive:** Lock finally means something and survives a refresh and other devices.
The day can be closed without lying about late orders. A wrong tap is recoverable and
attributable. `activity_log` has no anon DELETE policy, so history cannot be quietly erased.

**Negative:** Four schema objects for what began as a bug fix. `activity_log` grows
unbounded — there is no retention policy yet. Undo is single-step per event and does
not compose: undoing an older event after newer ones on the same row writes a stale
value back. "Who" is not captured — the app has no user identity, so the log records
what changed, not who changed it, which is weaker than the drawer's title suggests.

**When to revisit:** When the portal gains real user identity (then `activity_log`
wants an actor column), or when the log needs pruning.
