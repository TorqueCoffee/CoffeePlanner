# 0011 — Recoverable in-flight shipments (bought labels are read back from the DB)

- **Status**: Accepted
- **Date**: 2026-07-25

## Context

Step 5 shipped with an explicitly accepted limitation: the ship flow's state (`shipState`) lives in memory only, so a page reload between buying labels and fulfilling drops it. The labels stay bought in Shippo and the cost rows stay in `shipping_labels`, but the UI forgets, and recovery was "manual via Shippo/Shopify."

On 2026-07-25 that limitation cost a real shipment. Order #6738 (Lucky Dog, 4 boxes, $33.49 of labels) printed perfectly and was never fulfilled — no error, no customer email, no tracking. The fulfill endpoint was never called: iPad Safari discarded the app page while the label PDF was open in the second tab, so the operator came back to a clean order list with no Fulfill button and nothing indicating that four paid labels were sitting in the database. Re-opening the order offered to buy labels *again*.

The failure is silent in the worst way — it looks exactly like a completed job. Printing is the last visible act, so "the labels printed" reads as "the order shipped."

The obvious read-it-back fix collides with ADR 0004: `shipping_labels` has no anon SELECT policy on purpose, so cost/margin isn't readable from a page whose anon key is public. That same missing SELECT policy also turns out to break the `purchased`→`fulfilled` PATCH, which had been silently no-opping since day one (an `UPDATE … WHERE` must read the rows it matches; PostgREST returns 204 anyway).

## Options considered

- **Persist `shipState` to a new table / localStorage** — localStorage doesn't survive an app reinstall or a second device, and a new table duplicates what `shipping_labels` already holds. More state to keep honest.
- **Add an anon SELECT policy to `shipping_labels`** — one line, fixes both problems, but publishes cost and margin to anyone who views source. Directly reverses ADR 0004.
- **Server-side read endpoint using a service-role key** — keeps everything private, but adds a new secret and a deploy gate; this project's history shows open deploy gates sit for weeks.
- **`SECURITY DEFINER` RPCs returning only the non-cost columns** — no new secret, no anon SELECT, the exposed projection is written down in one place.
- **Auto-fulfill at the end of "print all"** — removes the second click entirely, but fires the customer email without confirmation and before anyone has looked at what came out of the printer.

## Decision

Bought labels are read back from the database through `SECURITY DEFINER` RPCs; the fulfill step stays a deliberate, human-confirmed action.

- `ship_labels_for_order(order_id)` rehydrates an opened order's labels (matched by `box_index`), so it lands on Step 3 — print + fulfill — instead of Step 1.
- `ship_labels_pending()` flags every order with labels bought and not fulfilled, right in the order list, with the button reading **Finish →** instead of **Ship →**.
- `mark_ship_labels_fulfilled(order_id)` replaces the PATCH and returns a row count, so `cost_updated` reports the truth.
- Neither read returns `cost`, `currency`, `zone`, `dest_zip` or `weight_lb` — ADR 0004 holds.
- `tracking_url` and `label_url` are now stored per label so a recovered shipment can be reprinted, not just fulfilled.

## Consequences

**Positive:** a paid shipment can no longer be silently abandoned — it is flagged in the list and restorable with one tap, on any device, after any reload. Re-buying is impossible (the buy step only ever targets boxes without a label). The long-broken status flip works, so `shipping_labels` finally reflects what shipped. No new secret, no deploy gate.

**Negative:** anyone holding the public anon key can call the RPCs and read tracking numbers and label URLs (a label PDF shows the ship-to address). That is a real widening of what the anon key reaches, accepted because the same key already reaches the B2B order list behind the same casual gate. The rehydrated pack is re-derived from the live order, so it can disagree with what was actually bought — surfaced as a red mismatch warning rather than resolved automatically.

**When to revisit:** if the ship flow ever needs to run outside the casual password gate, move these reads behind a serverless endpoint with a service-role key. If operators start ignoring the mismatch warning, make it block the fulfill button instead of just warning.

## Follow-up (2026-08-27)

The recovery net alone still lost #7034 — it was also never deployed for a month (see JOURNAL 2026-08-27), but even deployed it only helps if the operator goes back to the list. Added prevention on top, `index.html` only, so the silent skip is loud *before* it becomes a stranded shipment:

1. A `visibilitychange` prompt when the Ship tab regains focus with a printed-but-unfulfilled order open ("Fulfill now?"), armed once per print. This is the "auto-fulfill after print all" option from above, softened to a confirm that fires *after* the operator has seen the printout — which resolves the objection that killed the original.
2. A persistent red "NOT fulfilled" Step-3 state (pulsing Fulfill button, demoted print button) so the post-print screen never looks done.
3. A list-level red banner + one session alert whenever `ship_labels_pending()` is non-empty.
