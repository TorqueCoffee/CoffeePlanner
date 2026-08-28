# 0014 — Bagging tab is a spreadsheet grid, not a card list

- **Status**: Accepted (supersedes the Bagging layout choice in the 2026-08-27 V2 entry)
- **Date**: 2026-08-28

## Context

The V2 pass turned the Bagging list from a table into a card list, because the
V2 spec wanted a variant chip beside the coffee name, a single combined count,
and a per-row progress bar — all card-shaped. The `.dc.html` prototype still
reflects that.

The later handoff (`V2 update/handoff/CLAUDE_CODE_PROMPT.md` + `bagging-redesign.png`)
reverses it. Bagging is the first screen the team uses every morning and the one
they scan fastest. The operator's ask: see more coffees at once, and let the eye
run straight down aligned columns instead of re-parsing a card per row. Cards cost
vertical space (progress bar, trust line, wrapped tag row) and put the count in a
different horizontal position on every row.

## Options considered

- **Keep the V2 card list** — matches the prototype, but ~90px/row and nothing lines up.
- **HTML `<table>`** — real columns, but the existing table CSS fights the 2px-ink
  card aesthetic and cell wrapping for long names is awkward.
- **CSS grid with one shared `grid-template-columns`** (chosen) — header row and every
  data row use the same track list, so columns align; rows compress to ~44px; the
  name cell can wrap freely without disturbing the other columns.

## Decision

Bagging renders as a single `.bag-grid` container: a fixed header row and data
rows sharing `grid-template-columns: 24px minmax(200px,1fr) 100px 96px 132px 78px 64px`
(checkbox / name / bag size / source / qty / ±  / lock). No progress bar, no
"last bagged by" line. Stat totals and the Sort by control collapse into one slim
toolbar strip above the grid. Where the PNG and the `.dc.html` prototype disagree,
the PNG wins.

## Consequences

**Positive:** 8+ coffees visible on an iPad before scrolling; vertically aligned
columns; long single-origin names wrap instead of truncating; less markup per row.

**Negative:** Bagging and Roasting no longer share the `.row-card` component — two
row idioms to maintain. The `.dc.html` prototype is now stale for this tab.

**When to revisit:** if the team asks for per-row progress back, or if a future
redesign reunifies the two tabs' row components.
