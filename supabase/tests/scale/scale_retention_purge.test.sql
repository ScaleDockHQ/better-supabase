-- The outbox purge on the scale fixture (ADR 0607): 60,000 expired events in two
-- tenants and none. The purge
-- asks retention_for and is_held once per tenant and statement, not once per
-- row. The same predicate through the plain functions prints beside it. Set
-- bsb.scale_rows to resize (default 60,000).
begin;
select plan(4);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '60000'), true);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

insert into better_supabase.outbox_events (type, tenant_id, created_at)
select 'scale.purge',
  case g % 3 when 0 then '00000000-0000-4000-8000-000000000001'::uuid
             when 1 then '00000000-0000-4000-8000-000000000002'::uuid
             else null end,
  now() - interval '200 days'
from generate_series(1, current_setting('bsb.n')::int) g;

create temp table t0 as select clock_timestamp() as t;
grant all on t0 to public;

select count(*)::bigint as plain from better_supabase.outbox_events d
where d.type = 'scale.purge'
  and d.created_at < now() - coalesce(better_supabase.retention_for('outbox', d.tenant_id::text), interval '30 days')
  and not better_supabase.is_held('outbox', d.tenant_id::text) \gset
select diag('SCALE_MS retention_predicate_per_row=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select better_supabase.purge_outbox('30 days', 1000000, null) as purged \gset
select diag('SCALE_MS purge_outbox_memo=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select is(:purged::bigint, :plain::bigint, 'the purge deletes what the per-row predicate selects');
select ok(:purged::bigint > 0, 'the purge deleted rows');

-- A hold and a shorter policy are still honoured, as later statements of the same transaction.
select better_supabase.place_legal_hold('scale', '00000000-0000-4000-8000-000000000002', 'outbox');
select better_supabase.set_retention_policy('outbox', interval '10 days', '00000000-0000-4000-8000-000000000001');

insert into better_supabase.outbox_events (type, tenant_id, created_at)
select 'scale.held', '00000000-0000-4000-8000-000000000002'::uuid, now() - interval '200 days' from generate_series(1, 5)
union all
select 'scale.short', '00000000-0000-4000-8000-000000000001'::uuid, now() - interval '20 days' from generate_series(1, 5);

select better_supabase.purge_outbox('30 days', 1000, null);

select is((select count(*) from better_supabase.outbox_events where type = 'scale.held'), 5::bigint, 'a held tenant keeps its events');
select is((select count(*) from better_supabase.outbox_events where type = 'scale.short'), 0::bigint, 'a tenant policy shorter than the default purges sooner');

select * from finish();
rollback;

-- The statistics are not transactional; a doctor run after pgTAP would report this
-- fixture's temporary files (BS208).
select pg_stat_statements_reset() is not null as reset \gset
