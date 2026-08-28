-- Add the Probat as a second roaster alongside the Primo.
-- Primo is the baseline: the existing batch_size_lbs / shrinkage_pct columns
-- ARE the Primo values. Nothing is renamed and no existing value changes.

alter table public.green_coffee_settings
  -- null on purpose: an unset Probat batch size must show the roaster a
  -- "set this" prompt rather than silently computing a wrong batch count.
  add column if not exists probat_batch_lbs  numeric null,
  add column if not exists probat_shrink_pct numeric not null default 15,
  add column if not exists roast_machine     text    not null default 'primo';

alter table public.green_coffee_settings
  drop constraint if exists green_coffee_settings_roast_machine_check;

alter table public.green_coffee_settings
  add constraint green_coffee_settings_roast_machine_check
  check (roast_machine in ('primo','probat'));

comment on column public.green_coffee_settings.batch_size_lbs    is 'Primo batch size, lbs of green per batch.';
comment on column public.green_coffee_settings.shrinkage_pct     is 'Primo shrink %. green = roasted / (1 - pct/100).';
comment on column public.green_coffee_settings.probat_batch_lbs  is 'Probat batch size, lbs. Null = not yet set; UI prompts instead of calculating.';
comment on column public.green_coffee_settings.probat_shrink_pct is 'Probat shrink %. Defaults to 15 to match Primo until measured.';
comment on column public.green_coffee_settings.roast_machine     is 'Which roaster this coffee currently runs on: primo | probat.';
