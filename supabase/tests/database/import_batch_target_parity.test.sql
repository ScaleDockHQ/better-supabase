-- Set-based batch targets (ADR 0436): the customer entity writes through
-- public.import_customer_batch and customer_row through the one-row
-- public.import_customer, on the same data. Counts, rows, record map entries,
-- reruns, duplicate keys in one batch and a refused row must come out the same.
begin;
select plan(11);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

-- The row path gets its own kvk values, since kvk is unique per organization.
create function pg_temp.rk(items text) returns jsonb language sql as $$
  select replace(items::jsonb::text, '"kvk": "', '"kvk": "r')::jsonb
$$;

create temporary table out (name text primary key, result jsonb) on commit drop;
grant all on out to service_role;

select set_config('bsb.items', (select jsonb_agg(jsonb_build_object('key', 'p-' || g, 'scope', '', 'data', jsonb_build_object('name', 'Parity ' || g, 'kvk', 'pk' || g), 'refs', '{}'::jsonb))::text from generate_series(1, 200) g), true);

-- Run 1 writes through the batch target, run 2 through the row target.
select set_config('bsb.a', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'parity-batch', '{}'::jsonb) ->> 'id'), true);
select set_config('bsb.b', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'parity-row', '{}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('bsb.a')::uuid);
select better_supabase.mark_import_running(current_setting('bsb.b')::uuid);

insert into out values ('batch', better_supabase.import_upsert_batch(current_setting('bsb.a')::uuid, 'customer', current_setting('bsb.items')::jsonb));
insert into out values ('row', better_supabase.import_upsert_batch(current_setting('bsb.b')::uuid, 'customer_row', pg_temp.rk(current_setting('bsb.items'))));

select is(
  (select result - 'dryRun' - 'warnings' from out where name = 'batch'),
  (select result - 'dryRun' - 'warnings' from out where name = 'row'),
  'the counts and errors are equal'
);
select is((select (result ->> 'inserted')::int from out where name = 'batch'), 200, 'the batch path inserted every item');

select is(
  (select count(*)::int from public.customers where name like 'Parity %'),
  400,
  'both paths wrote their 200 customers'
);
select is(
  (select md5(string_agg(name || '|' || status, ',' order by name)) from public.customers c
    join better_supabase.import_records r on r.subject_id = c.id::text and r.source = 'parity-batch'),
  (select md5(string_agg(name || '|' || status, ',' order by name)) from public.customers c
    join better_supabase.import_records r on r.subject_id = c.id::text and r.source = 'parity-row'),
  'the customer rows are equal'
);
select is(
  (select jsonb_build_array(count(*), count(distinct content_hash), min(subject_type)) from better_supabase.import_records where source = 'parity-batch'),
  (select jsonb_build_array(count(*), count(distinct content_hash), min(subject_type)) from better_supabase.import_records where source = 'parity-row'),
  'the record maps have the same shape'
);

select better_supabase.finish_import_run(current_setting('bsb.a')::uuid);
select better_supabase.finish_import_run(current_setting('bsb.b')::uuid);

-- A rerun: equal content is unchanged, a changed name updates, on both paths.
select set_config('bsb.items2', (select jsonb_agg(jsonb_build_object('key', 'p-' || g, 'scope', '', 'data', jsonb_build_object('name', 'Parity ' || g || case when g <= 50 then ' v2' else '' end, 'kvk', 'pk' || g), 'refs', '{}'::jsonb))::text from generate_series(1, 200) g), true);
select set_config('bsb.a', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'parity-batch', '{}'::jsonb) ->> 'id'), true);
select set_config('bsb.b', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'parity-row', '{}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('bsb.a')::uuid);
select better_supabase.mark_import_running(current_setting('bsb.b')::uuid);
insert into out values ('batch2', better_supabase.import_upsert_batch(current_setting('bsb.a')::uuid, 'customer', current_setting('bsb.items2')::jsonb));
insert into out values ('row2', better_supabase.import_upsert_batch(current_setting('bsb.b')::uuid, 'customer_row', pg_temp.rk(current_setting('bsb.items2'))));

select is(
  (select result - 'dryRun' - 'warnings' from out where name = 'batch2'),
  (select result - 'dryRun' - 'warnings' from out where name = 'row2'),
  'a rerun counts the same on both paths'
);
select is((select jsonb_build_array((result ->> 'updated')::int, (result ->> 'unchanged')::int) from out where name = 'batch2'), '[50, 150]'::jsonb, 'fifty updated, the rest unchanged');
select is((select count(*)::int from public.customers where name like 'Parity % v2'), 100, 'both paths renamed fifty');

-- The same key twice in one batch: the second sees the first on both paths.
select better_supabase.finish_import_run(current_setting('bsb.a')::uuid);
select better_supabase.finish_import_run(current_setting('bsb.b')::uuid);
select set_config('bsb.a', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'parity-batch', '{}'::jsonb) ->> 'id'), true);
select set_config('bsb.b', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'parity-row', '{}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('bsb.a')::uuid);
select better_supabase.mark_import_running(current_setting('bsb.b')::uuid);
select set_config('bsb.dup', '[{"key":"d-1","data":{"name":"Dup one","kvk":"d1"}},{"key":"d-1","data":{"name":"Dup one again","kvk":"d1"}},{"key":"d-2","data":{"name":"Dup two","kvk":"d2"}}]', true);
insert into out values ('batch3', better_supabase.import_upsert_batch(current_setting('bsb.a')::uuid, 'customer', current_setting('bsb.dup')::jsonb));
insert into out values ('row3', better_supabase.import_upsert_batch(current_setting('bsb.b')::uuid, 'customer_row', pg_temp.rk(current_setting('bsb.dup'))));
select is(
  (select result - 'dryRun' - 'warnings' from out where name = 'batch3'),
  (select result - 'dryRun' - 'warnings' from out where name = 'row3'),
  'a repeated key in one batch counts the same'
);

-- A refused row (no name): the batch raises, falls back to one row at a time,
-- and reports the same error while the good rows land.
select better_supabase.finish_import_run(current_setting('bsb.a')::uuid);
select better_supabase.finish_import_run(current_setting('bsb.b')::uuid);
select set_config('bsb.a', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'parity-batch', '{}'::jsonb) ->> 'id'), true);
select set_config('bsb.b', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'parity-row', '{}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('bsb.a')::uuid);
select better_supabase.mark_import_running(current_setting('bsb.b')::uuid);
select set_config('bsb.bad', '[{"key":"b-1","data":{"name":"Bad ok one","kvk":"b1"}},{"key":"b-2","data":{"kvk":"b2"}},{"key":"b-3","data":{"name":"Bad ok three","kvk":"b3"}}]', true);
insert into out values ('batch4', better_supabase.import_upsert_batch(current_setting('bsb.a')::uuid, 'customer', current_setting('bsb.bad')::jsonb));
insert into out values ('row4', better_supabase.import_upsert_batch(current_setting('bsb.b')::uuid, 'customer_row', pg_temp.rk(current_setting('bsb.bad'))));
select is(
  (select jsonb_build_array((result ->> 'inserted')::int, jsonb_array_length(result -> 'errors'), result -> 'errors' -> 0 ->> 'key') from out where name = 'batch4'),
  (select jsonb_build_array((result ->> 'inserted')::int, jsonb_array_length(result -> 'errors'), result -> 'errors' -> 0 ->> 'key') from out where name = 'row4'),
  'a refused row is reported the same way and the others land'
);
select is((select count(*)::int from public.customers where name like 'Bad ok %'), 4, 'the good rows of both paths landed');

select * from finish();
rollback;
