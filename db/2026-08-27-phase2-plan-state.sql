-- Phase 2: make the roasting plan hold still.
--   1. persist the per-day roasting freeze (Lock)
--   2. give daily_plan a real arrival time, so "came in after lock" is knowable
--   3. plan_state: one row per team per day, recording finalization
--   4. activity_log: who changed what, with a payload for Undo

-- 1. Freeze. Null = not frozen. Set = the roasted-lbs demand this coffee was
--    locked at; later pulls and Add Order lines must not move it.
alter table public.roasting_progress
  add column if not exists locked_roasted_lbs numeric null;

comment on column public.roasting_progress.locked_roasted_lbs is
  'Frozen roasted-lbs demand for this coffee on this plan_date. Null = tracking the live plan.';

-- 2. Arrival time. updated_at moves every time someone taps +, so it cannot
--    answer "did this line arrive after we finalized?". Existing rows are
--    backfilled from updated_at as the closest available proxy.
alter table public.daily_plan
  add column if not exists created_at timestamptz null default now();

update public.daily_plan set created_at = updated_at where created_at is null;

comment on column public.daily_plan.created_at is
  'When this line first appeared. Compared against plan_state.finalized_at to flag late orders.';

-- 3. Plan state. One row per team per production day.
create table if not exists public.plan_state (
  team_id      text        not null,
  plan_date    date        not null default current_date,
  finalized_at timestamptz null,
  updated_at   timestamptz not null default now(),
  primary key (team_id, plan_date)
);

comment on table public.plan_state is
  'Per-day production plan state. finalized_at null = open; set = the plan was frozen at that moment.';

alter table public.plan_state enable row level security;

drop policy if exists "anon read plan_state"   on public.plan_state;
drop policy if exists "anon write plan_state"  on public.plan_state;
drop policy if exists "anon update plan_state" on public.plan_state;
create policy "anon read plan_state"   on public.plan_state for select to anon using (true);
create policy "anon write plan_state"  on public.plan_state for insert to anon with check (true);
create policy "anon update plan_state" on public.plan_state for update to anon using (true) with check (true);

-- 4. Activity log. Append-only; undo marks a row rather than deleting it, so
--    the history stays honest about what was undone.
create table if not exists public.activity_log (
  id         uuid        primary key default gen_random_uuid(),
  team_id    text        not null,
  plan_date  date        not null default current_date,
  kind       text        not null,
  text       text        not null,
  undo       jsonb       null,
  undone     boolean     not null default false,
  created_at timestamptz not null default now()
);

create index if not exists activity_log_team_date_idx
  on public.activity_log (team_id, plan_date, created_at desc);

comment on column public.activity_log.undo is
  'Payload needed to reverse this event: {table, id, column, prev}. Null = not undoable.';

-- Append-only by design: anon gets read/insert/update (to flag a row undone)
-- but deliberately NO delete policy, so history cannot be quietly erased.
alter table public.activity_log enable row level security;

drop policy if exists "anon read activity_log"   on public.activity_log;
drop policy if exists "anon write activity_log"  on public.activity_log;
drop policy if exists "anon update activity_log" on public.activity_log;
create policy "anon read activity_log"   on public.activity_log for select to anon using (true);
create policy "anon write activity_log"  on public.activity_log for insert to anon with check (true);
create policy "anon update activity_log" on public.activity_log for update to anon using (true) with check (true);
