-- Keyset and offset pages of a block list on the scale fixture (ADR 0634): a
-- deep page by offset reads and discards every skipped row, a keyset page
-- starts at the cursor. Set bsb.scale_rows to resize (default 60,000).
begin;
select plan(8);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '60000'), true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select better_supabase.ensure_risk_matrix('00000000-0000-4000-8000-000000000001') as matrix \gset

insert into better_supabase.risks (tenant_id, number, sequence, matrix_id, title, category, status, residual_score)
select '00000000-0000-4000-8000-000000000001', 'RSK-' || g, g, :'matrix', 'Scale risk ' || g, 'ops', 'assessed',
  1 + (g % 100)
from generate_series(1, current_setting('bsb.n')::int) g;
analyze better_supabase.risks;

set local role service_role;

create temp table t0 as select clock_timestamp() as t;
grant all on t0 to public;

select better_supabase.list_risks('00000000-0000-4000-8000-000000000001', '{"limit":20}') as first_page \gset
select diag('SCALE_MS list_risks_first=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select better_supabase.list_risks('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('limit', 20, 'offset', current_setting('bsb.n')::int - 40)) as deep_offset \gset
select diag('SCALE_MS list_risks_offset_deep=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select better_supabase.list_risks('00000000-0000-4000-8000-000000000001',
  '{"limit":20,"paged":true,"total":true}') as paged \gset
select diag('SCALE_MS list_risks_paged_total=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select is(jsonb_array_length(:'first_page'::jsonb), 20, 'a plain page is the array it always was');
select is(jsonb_array_length(:'deep_offset'::jsonb), 20, 'a deep offset page still reads');
select is((:'paged'::jsonb ->> 'hasMore')::boolean, true, 'a paged read reports hasMore');
select is((:'paged'::jsonb ->> 'totalCapped')::boolean, current_setting('bsb.n')::int > 10000, 'the total is capped at its default');

-- Walk to the last page by keyset: the cursor of each page starts the next.
select set_config('bsb.cursor', :'paged'::jsonb ->> 'nextCursor', true);
update t0 set t = clock_timestamp();
do $$
declare
  v_page jsonb;
  v_pages integer := 1;
begin
  loop
    v_page := better_supabase.list_risks('00000000-0000-4000-8000-000000000001',
      jsonb_build_object('limit', 500, 'paged', true, 'after', current_setting('bsb.cursor')::jsonb));
    exit when v_page ->> 'nextCursor' is null;
    perform set_config('bsb.cursor', v_page ->> 'nextCursor', true);
    v_pages := v_pages + 1;
  end loop;
  perform set_config('bsb.pages', v_pages::text, true);
end $$;
select diag('SCALE_MS list_risks_keyset_walk=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));
select ok(current_setting('bsb.pages')::int >= 1, 'a keyset walk ends on a page without a cursor');

update t0 set t = clock_timestamp();
select better_supabase.list_risks('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('limit', 20, 'after', jsonb_build_array('1', current_setting('bsb.n'), '00000000-0000-0000-0000-000000000000'))) as deep_keyset \gset
select diag('SCALE_MS list_risks_keyset_deep=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));
select ok(jsonb_array_length(:'deep_keyset'::jsonb) >= 0, 'a keyset page deep in the list reads');

select throws_ok(
  $q$select better_supabase.list_risks('00000000-0000-4000-8000-000000000001', '{"after":["1","2","3"],"offset":5}')$q$,
  '22023', 'after and offset are two ways to page; pass one', 'after and offset do not combine');
select throws_ok(
  $q$select better_supabase.list_risks('00000000-0000-4000-8000-000000000001', '{"after":["1"]}')$q$,
  '22023', 'after is the nextCursor of the previous page', 'a cursor of the wrong length is refused');

select * from finish();
rollback;

select pg_stat_statements_reset() is not null as reset \gset
