-- A repeated dedupe key moves a waiting job earlier, never later, and keeps one job.
begin;
select plan(4);

set local role service_role;

create temporary table ids (name text primary key, id bigint) on commit drop;
insert into ids
select 'first', better_supabase.enqueue_job('dedupe_test', '{}', 3600, 5, 'k1');

select is(
  (select count(*)::int from better_supabase.claim_jobs('dedupe_test', 60, 10)),
  0,
  'the delayed job is not due'
);

select is(
  better_supabase.enqueue_job('dedupe_test', '{}', 0, 5, 'k1'),
  (select id from ids where name = 'first'),
  'the second enqueue returns the first job'
);

select is(
  (select count(*)::int from better_supabase.claim_jobs('dedupe_test', 60, 10)),
  1,
  'the shorter delay made the job due'
);

insert into ids
select 'second', better_supabase.enqueue_job('dedupe_test', '{}', 0, 5, 'k2');

select is(
  better_supabase.enqueue_job('dedupe_test', '{}', 3600, 5, 'k2'),
  (select id from ids where name = 'second'),
  'a longer delay keeps the sooner time and the same job'
);

select * from finish();
rollback;
