-- The chunk lifecycle (ADR 1223): a done chunk drops its items, finish refuses a
-- run with open chunks, a final failure fails the run, a retried chunk reaches
-- the queue under a :retry: key after the first message was archived, the run
-- reports its chunks, and maintenance clears the items of ended runs.
begin;
select plan(13);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select set_config('bsb.run', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'chunk-life', '{}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('bsb.run')::uuid);

select better_supabase.store_import_chunk(current_setting('bsb.run')::uuid, 'customer', 0,
  (select jsonb_agg(jsonb_build_object('key', 'life-' || g, 'scope', '', 'data', jsonb_build_object('name', 'Life ' || g, 'kvk', 'life' || g), 'refs', '{}'::jsonb)) from generate_series(1, 5) g));
select better_supabase.store_import_chunk(current_setting('bsb.run')::uuid, 'customer', 1,
  (select jsonb_agg(jsonb_build_object('key', 'life-b' || g, 'scope', '', 'data', jsonb_build_object('name', 'Life b' || g, 'kvk', 'lifeb' || g), 'refs', '{}'::jsonb)) from generate_series(1, 5) g));

select ok(((better_supabase.get_import_run(current_setting('bsb.run')::uuid) -> 'chunks' ->> 'bytes')::int) > 0, 'the run reports the bytes its chunks hold');

select is((better_supabase.process_import_chunk(current_setting('bsb.run')::uuid, 'customer', 0) ->> 'inserted')::int, 5, 'a chunk is written');
select is((select items from better_supabase.import_chunks where run_id = current_setting('bsb.run')::uuid and chunk = 0), null, 'a done chunk drops its items');
select isnt((select result from better_supabase.import_chunks where run_id = current_setting('bsb.run')::uuid and chunk = 0), null, 'and keeps its result');

select throws_ok(
  format($$select better_supabase.finish_import_run(%L::uuid)$$, current_setting('bsb.run')),
  'PT409', 'the import has chunks that are not done', 'finish refuses a run with an open chunk');

-- The queue: the first message is archived, the chunk fails, and the retry reaches the queue.
select better_supabase.enqueue_import_chunks(current_setting('bsb.run')::uuid, 'customer', 2);
reset role;
select pgmq.archive('imports', (select array_agg(msg_id) from pgmq.q_imports where message -> 'payload' ->> 'run' = current_setting('bsb.run')));
set local role service_role;
select better_supabase.fail_import_chunk(current_setting('bsb.run')::uuid, 'customer', 1, 'worker gave up');
select better_supabase.enqueue_import_chunks(current_setting('bsb.run')::uuid, 'customer', 2);
reset role;
select is(
  (select count(*)::int from pgmq.q_imports where message -> 'payload' ->> 'run' = current_setting('bsb.run') and message ->> 'dedupe_key' like '%:1:retry:%'),
  1, 'a retried chunk reaches the queue under a :retry: key');
set local role service_role;
select is((select status from better_supabase.import_chunks where run_id = current_setting('bsb.run')::uuid and chunk = 1), 'pending', 'the retry made the failed chunk pending');

-- A final failure fails the run with the chunk's message.
select is(better_supabase.fail_import_chunk(current_setting('bsb.run')::uuid, 'customer', 1, 'statement timeout', true), true, 'a final failure marks the chunk');
select is((better_supabase.get_import_run(current_setting('bsb.run')::uuid) ->> 'status'), 'failed', 'and fails the run');
select is(
  (better_supabase.get_import_run(current_setting('bsb.run')::uuid) -> 'errors' -> -1 ->> 'code'),
  'IMPORT_CHUNK_FAILED', 'with the chunk in its errors');
select is((better_supabase.get_import_run(current_setting('bsb.run')::uuid) -> 'chunks' ->> 'failed')::int, 1, 'the run counts the failed chunk');

-- Maintenance keeps a failed chunk's items until keepFailedItems, then clears them.
reset role;
select is((better_supabase.import_chunk_maintenance() ->> 'cleared')::int, 0, 'a fresh failure keeps its items');
update better_supabase.import_chunks set done_at = now() - interval '8 days' where run_id = current_setting('bsb.run')::uuid and chunk = 1;
select is((better_supabase.import_chunk_maintenance() ->> 'cleared')::int, 1, 'an expired failure loses its items');

select * from finish();
rollback;
