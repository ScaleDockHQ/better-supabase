-- enqueue_import_chunks puts one job per chunk on the queue named imports
-- (the name was once passed with its quotes, a queue no worker reads).
begin;
select plan(3);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select set_config('better_supabase.run', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'chunk-queue', '{}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('better_supabase.run')::uuid);

select is(better_supabase.enqueue_import_chunks(current_setting('better_supabase.run')::uuid, 'customer', 2), 2, 'two chunks are queued');

reset role;
select ok(to_regclass('pgmq.q_imports') is not null, 'the queue is named imports');
select is(
  (select count(*)::int from pgmq.q_imports where message -> 'payload' ->> 'run' = current_setting('better_supabase.run')),
  2,
  'each chunk is a message on it'
);

select * from finish();
rollback;
