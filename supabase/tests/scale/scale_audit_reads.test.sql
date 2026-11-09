-- Audit reads on the scale fixture: the tenant-led indexes with an id tiebreaker
-- serve a page, an actor filter and an event type filter without a sort, the
-- summary form leaves out the record JSON, get_audit_event returns the full
-- entry, the capped count stops at its cap and audit_event_types skips through
-- the event type index. Set bsb.scale_rows to resize (default 60,000).
begin;
select plan(9);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '60000'), true);

insert into better_supabase.audit_events (
  table_name, record_id, op, new_record, actor_id, tenant_id, occurred_at, event_type, summary
)
select 'tasks', g::text, 'event', jsonb_build_object('n', g),
  ('00000000-0000-4000-8000-0000000000a' || (1 + g % 3))::uuid,
  '00000000-0000-4000-8000-000000000001',
  now() - (g || ' minutes')::interval,
  'scale.event_' || (g % 20), 'Scale entry ' || g
from generate_series(1, current_setting('bsb.n')::int) g;
analyze better_supabase.audit_events;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;

create temp table t0 as select clock_timestamp() as t;
grant all on t0 to public;

select better_supabase.list_audit_events(
  for_tenants => array['00000000-0000-4000-8000-000000000001'::uuid]) as page \gset
select diag('SCALE_MS audit_page=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));
select is(jsonb_array_length(:'page'::jsonb), 50, 'a page has 50 entries');

select better_supabase.list_audit_events(
  for_tenants => array['00000000-0000-4000-8000-000000000001'::uuid], entry_fields => 'summary') as summary \gset
select ok(not (:'summary'::jsonb -> 0 ? 'new') and not (:'summary'::jsonb -> 0 ? 'metadata'), 'the summary form leaves out the record JSON');
select ok((:'page'::jsonb -> 0) ? 'new', 'the full form keeps it');

select better_supabase.get_audit_event((:'page'::jsonb -> 0 ->> 'id')) -> 'new' is not null as got \gset
select ok(:'got'::boolean, 'get_audit_event returns the full entry');

select is(
  better_supabase.count_audit_events(
    for_tenants => array['00000000-0000-4000-8000-000000000001'::uuid], cap => 1000),
  1000::bigint, 'the capped count stops at its cap');

select ok(
  cardinality(better_supabase.audit_event_types(array['00000000-0000-4000-8000-000000000001'::uuid])) >= 20,
  'audit_event_types finds the distinct types');

-- The plans the dynamic queries produce: the index orders the rows, so there is no sort node.
create temp table plans (name text, plan text);
grant all on plans to public;

do $$
declare v_plan jsonb;
begin
  execute $q$explain (format json) select l.id from better_supabase.audit_events l
    where l.tenant_id = any (array['00000000-0000-4000-8000-000000000001'::uuid])
    order by l.occurred_at desc, l.id desc limit 50$q$ into v_plan;
  insert into plans values ('page', v_plan::text);
  execute $q$explain (format json) select l.id from better_supabase.audit_events l
    where l.tenant_id = any (array['00000000-0000-4000-8000-000000000001'::uuid]) and l.actor_id = any (array['00000000-0000-4000-8000-0000000000a2'::uuid])
    order by l.occurred_at desc, l.id desc limit 50$q$ into v_plan;
  insert into plans values ('actor', v_plan::text);
  execute $q$explain (format json) select l.id from better_supabase.audit_events l
    where l.tenant_id = any (array['00000000-0000-4000-8000-000000000001'::uuid]) and l.event_type = any (array['scale.event_3'])
    order by l.occurred_at desc, l.id desc limit 50$q$ into v_plan;
  insert into plans values ('type', v_plan::text);
end $$;

select ok((select plan from plans where name = 'page') not like '%"Sort"%', 'a page reads in index order, with no sort');
select ok((select plan from plans where name = 'actor') not like '%"Sort"%', 'an actor filter reads in index order, with no sort');
select ok((select plan from plans where name = 'type') not like '%"Sort"%', 'an event type filter reads in index order, with no sort');

select * from finish();
rollback;

-- The statistics are not transactional; a doctor run after pgTAP would report this
-- fixture's temporary files (BS208).
select pg_stat_statements_reset() is not null as reset \gset
