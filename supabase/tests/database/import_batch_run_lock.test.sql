-- import_upsert_batch reads the run without a row lock, so two batches of one
-- run don't wait on each other; only the counts update at its end locks the
-- row. The lock itself needs two sessions, so this checks the function body
-- and that the counts of two batches in one transaction add up.
begin;
select plan(4);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select ok(
  (select position('for update' in p.prosrc) = 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'better_supabase' and p.proname = 'import_upsert_batch'),
  'import_upsert_batch takes no row lock when it reads the run'
);

select set_config('better_supabase.run', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'run-lock', '{}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('better_supabase.run')::uuid);

select is(
  (better_supabase.import_upsert_batch(current_setting('better_supabase.run')::uuid, 'customer', jsonb_build_array(
    jsonb_build_object('key', 'rl-1', 'scope', '', 'data', jsonb_build_object('name', 'Run lock one', 'kvk', '91'), 'refs', '{}'::jsonb)
  )) ->> 'inserted')::int,
  1,
  'the first batch inserts its row'
);
select is(
  (better_supabase.import_upsert_batch(current_setting('better_supabase.run')::uuid, 'customer', jsonb_build_array(
    jsonb_build_object('key', 'rl-2', 'scope', '', 'data', jsonb_build_object('name', 'Run lock two', 'kvk', '92'), 'refs', '{}'::jsonb)
  )) ->> 'inserted')::int,
  1,
  'the second batch inserts its row'
);
select is(
  (select (counts -> 'customer' ->> 'inserted')::int from better_supabase.import_runs where id = current_setting('better_supabase.run')::uuid),
  2,
  'the counts of both batches add up'
);

select * from finish();
rollback;
