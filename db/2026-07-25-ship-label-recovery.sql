-- 2026-07-25 · ship label recovery (migration name: ship_label_recovery)
--
-- B2B cubic shipping: make an in-flight shipment recoverable after the app page
-- is reloaded or discarded (iPad Safari does this while the label PDF is open in
-- a second tab). The bought labels are the durable record; the UI needs to be
-- able to read them back, otherwise an order silently never gets fulfilled.
--
-- Reads go through SECURITY DEFINER functions rather than a blanket anon SELECT
-- policy, so ADR 0004 still holds: cost / currency / zone / weight stay
-- unreadable to the public anon key. Only what's needed to resume and fulfill a
-- shipment is exposed.

alter table public.shipping_labels
  add column if not exists tracking_url text,
  add column if not exists label_url text;

-- Every label bought for one order (to rehydrate the ship screen).
create or replace function public.ship_labels_for_order(p_order_id text)
returns table (
  order_id text,
  order_name text,
  box_index integer,
  box_count integer,
  tracking_number text,
  tracking_url text,
  label_url text,
  shippo_object_id text,
  status text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select sl.order_id, sl.order_name, sl.box_index, sl.box_count,
         sl.tracking_number, sl.tracking_url, sl.label_url,
         sl.shippo_object_id, sl.status, sl.created_at
  from public.shipping_labels sl
  where sl.order_id = p_order_id
  order by sl.box_index
$$;

-- Orders with labels bought but not yet fulfilled (to flag them in the list).
create or replace function public.ship_labels_pending()
returns table (
  order_id text,
  order_name text,
  labels_bought bigint,
  box_count integer,
  bought_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select sl.order_id,
         min(sl.order_name) as order_name,
         count(*) as labels_bought,
         max(sl.box_count) as box_count,
         max(sl.created_at) as bought_at
  from public.shipping_labels sl
  where sl.status = 'purchased'
  group by sl.order_id
$$;

-- Status flip after a successful fulfillment. This exists because a PostgREST
-- PATCH cannot do it: an UPDATE ... WHERE has to READ the rows it matches, and
-- with RLS on and no SELECT policy (deliberate, ADR 0004) the WHERE matches
-- nothing — PostgREST then returns 204 with Content-Range */0, which the caller
-- read as success. Returns the number of rows actually flipped, so the endpoint
-- can report the truth instead of assuming it.
create or replace function public.mark_ship_labels_fulfilled(p_order_id text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n integer;
begin
  update public.shipping_labels sl
     set status = 'fulfilled'
   where sl.order_id = p_order_id
     and sl.status is distinct from 'fulfilled';
  get diagnostics n = row_count;
  return n;
end
$$;

grant execute on function public.ship_labels_for_order(text) to anon, authenticated;
grant execute on function public.ship_labels_pending() to anon, authenticated;
grant execute on function public.mark_ship_labels_fulfilled(text) to anon, authenticated;

-- Backfill: #6738 (Lucky Dog, 2026-07-25) was fulfilled in Shopify but its rows
-- never flipped, because of the PATCH bug above. Same for every earlier order
-- whose fulfillment succeeded — safe to run, it only touches this one order.
select public.mark_ship_labels_fulfilled('gid://shopify/Order/7316546322652');
