-- better_supabase.broadcast_topic(): the default payload carries the key and
-- the topic values, never a column the subscriber's grants hide; a before
-- trigger is refused; a value topics don't allow skips the send.
begin;
select plan(7);

create table public.bs_rt_secrets (
  id uuid primary key default gen_random_uuid(),
  team text not null,
  secret text not null
);
grant select (id, team) on public.bs_rt_secrets to authenticated;

create trigger bs_rt_keys after insert on public.bs_rt_secrets
  for each row execute function better_supabase.broadcast_topic('team:{team}', 'changed');

insert into public.bs_rt_secrets (id, team, secret)
values ('00000000-0000-4000-8000-0000000000a1', 'red', 'hunter2');

select is(
  (select payload from realtime.messages where topic = 'team:red'),
  jsonb_build_object(
    'operation', 'INSERT',
    'schema', 'public',
    'table', 'bs_rt_secrets',
    'id', '00000000-0000-4000-8000-0000000000a1',
    'values', jsonb_build_object('team', 'red')
  ),
  'the default payload is the key and the topic values'
);

select ok(
  not exists (
    select 1 from realtime.messages
    where topic = 'team:red' and payload::text like '%hunter2%'
  ),
  'a column authenticated cannot select stays out of the payload'
);

create trigger bs_rt_rows after update on public.bs_rt_secrets
  for each row execute function better_supabase.broadcast_topic('rows:{team}', '', '', 'row');

update public.bs_rt_secrets set secret = 'hunter3' where team = 'red';

select is(
  (select payload -> 'record' ->> 'secret' from realtime.messages where topic = 'rows:red'),
  'hunter3',
  'payload row sends the whole row'
);

select lives_ok(
  $$insert into public.bs_rt_secrets (team, secret) values ('a b', 'x')$$,
  'a value topics do not allow does not fail the write'
);

select is(
  (select count(*)::int from realtime.messages where topic like 'team:a%'),
  0,
  'and nothing is sent for it'
);

select lives_ok(
  $$insert into public.bs_rt_secrets (team, secret) values ('blue', 'y')$$,
  'the next write still broadcasts'
);

create trigger bs_rt_before before insert on public.bs_rt_secrets
  for each row execute function better_supabase.broadcast_topic('team:{team}', '');

select throws_ok(
  $$insert into public.bs_rt_secrets (team, secret) values ('green', 'z')$$,
  '39P01',
  null,
  'broadcast_topic() refuses to run as a before trigger'
);

select * from finish();
rollback;
