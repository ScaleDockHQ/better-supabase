-- better_supabase.get_job: one message's run record without its payload, the
-- source behind queue.get and the queue job source (ADR 1076).
begin;
select plan(7);

set local role service_role;

create temporary table ids (name text primary key, id bigint) on commit drop;
insert into ids
select 'first', better_supabase.enqueue_job('get_job_test', '{"secret":1}', 0, 3, null);

select is(
  better_supabase.get_job('get_job_test', 0::bigint),
  null,
  'an unknown message reads as null'
);
select is(
  (select better_supabase.get_job('get_job_test', id) ->> 'state' from ids),
  'waiting',
  'a queued message is waiting'
);
select is(
  (select better_supabase.get_job('get_job_test', id) ? 'payload' from ids),
  false,
  'the record never holds the payload'
);

select is(
  (select count(*)::int from better_supabase.claim_jobs('get_job_test', 60, 10)),
  1,
  'a worker claims it'
);
select is(
  (select better_supabase.get_job('get_job_test', id) ->> 'state' from ids),
  'running',
  'a claimed message is running'
);

select ok(
  (select better_supabase.complete_job('get_job_test', id, 1) from ids),
  'the worker completes it'
);
select is(
  (select better_supabase.get_job('get_job_test', id) ->> 'state' from ids),
  'done',
  'an archived message is done'
);

select * from finish();
rollback;
