-- Scale fixture (ADR 0424): 60,000 customers in one tenant and 12,000
-- attachments on them, read as a signed-in member. Set bsb.scale_rows to
-- shrink it. The numbers go to diag lines (SCALE_MS) so a change shows its
-- effect; the assertions only hold the plan shape.
begin;
select plan(2);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '60000'), true);

insert into public.customers (organization_id, name)
select '00000000-0000-4000-8000-000000000001', 'Scale ' || g
from generate_series(1, current_setting('bsb.n')::int) g;

insert into better_supabase.attachments (tenant_id, bucket, subject_type, subject_id, name, mime_type, size, uploaded_by)
select '00000000-0000-4000-8000-000000000001', 'attachments', 'customer', c.id::text, 'f' || row_number() over (), 'text/plain', 10,
  '00000000-0000-4000-8000-0000000000a1'
from (select id from public.customers where name like 'Scale %' limit current_setting('bsb.n')::int / 5) c;
analyze public.customers;
analyze better_supabase.attachments;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;

create temp table t0 as select clock_timestamp() as t;
grant all on t0 to public;
select count(*) from better_supabase.attachments;
select diag('SCALE_MS attachments_count=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select count(*) from (select id from better_supabase.attachments limit 50) x;
select diag('SCALE_MS attachments_page50=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select count(*) from public.customers;
select diag('SCALE_MS customers_exact_count=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select ok(true, 'the fixture loads');
select ok(true, 'the measurements ran');
select * from finish();
rollback;

-- The statistics are not transactional; a doctor run after pgTAP would report this
-- fixture's temporary files (BS208).
select pg_stat_statements_reset() is not null as reset \gset
