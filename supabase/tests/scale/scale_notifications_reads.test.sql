-- Notification reads on the scale fixture: the inbox query matches the partial
-- inbox index, so a page reads in index order; the keyset page reports hasMore
-- and a capped total; the badge counts stop at their cap. Set bsb.scale_rows to
-- resize (default 60,000).
begin;
select plan(7);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '60000'), true);

with e as (
  insert into better_supabase.notification_events (id, tenant_id, type, summary, created_at)
  select gen_random_uuid(), '00000000-0000-4000-8000-000000000001', 'scale.type_' || (g % 4),
    'Scale ' || g, now() - (g || ' minutes')::interval
  from generate_series(1, current_setting('bsb.n')::int) g
  returning id, tenant_id, created_at
)
insert into better_supabase.notification_recipients (event_id, tenant_id, user_id, read_at, created_at)
select id, tenant_id, '00000000-0000-4000-8000-0000000000a1',
  case when abs(hashtext(id::text)) % 10 = 0 then null else created_at end, created_at
from e;
analyze better_supabase.notification_recipients;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;

create temp table t0 as select clock_timestamp() as t;
grant all on t0 to public;

select better_supabase.notification_page(max_items => 20) as page \gset
select diag('SCALE_MS notification_page=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));
select is(jsonb_array_length(:'page'::jsonb -> 'items'), 20, 'a page has 20 items');
select is((:'page'::jsonb ->> 'hasMore')::boolean, true, 'an older page exists');
select is((:'page'::jsonb ->> 'total')::int, 10000, 'the total stops at its default cap');
select is((:'page'::jsonb ->> 'totalCapped')::boolean, true, 'the page says the total was capped');

update t0 set t = clock_timestamp();
select better_supabase.notification_counts() as counts \gset
select diag('SCALE_MS notification_counts=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));
select is((:'counts'::jsonb ->> 'unread')::int, 100, 'the unread count stops at its cap');
select is(
  (better_supabase.notification_counts(cap => null) ->> 'unread')::int > 100, true, 'a null cap counts every unread row');

select better_supabase.list_notifications(
  before => now() - interval '1 day', before_id => 'ffffffff-ffff-ffff-ffff-ffffffffffff', max_items => 5) as older \gset
select is(jsonb_array_length(:'older'::jsonb), 5, 'a keyset page continues from its cursor');

select * from finish();
rollback;

-- The statistics are not transactional; a doctor run after pgTAP would report this
-- fixture's temporary files (BS208).
select pg_stat_statements_reset() is not null as reset \gset
