-- better_supabase.broadcast_topic(): the default payload carries the key and
-- the topic values, never a column the subscriber's grants hide; a before or
-- statement trigger is refused; a null value or a value topics don't allow
-- skips the send.
begin;
select plan(13);

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

select ok(
  (select bool_and(private) from realtime.messages where topic = 'team:red'),
  'a topic is private unless the trigger passes false'
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

select is(
  (select count(*)::int from realtime.messages where topic = 'team:blue'),
  1,
  'and its message is sent'
);

create table public.bs_rt_nullable (
  id uuid primary key default gen_random_uuid(),
  team text
);
create trigger bs_rt_nullable after insert on public.bs_rt_nullable
  for each row execute function better_supabase.broadcast_topic('nullable:{team}', 'changed');

insert into public.bs_rt_nullable (team) values (null);

select is(
  (select count(*)::int from realtime.messages where topic like 'nullable:%'),
  0,
  'a null topic value skips the send'
);

create table public.bs_rt_alias (
  id uuid primary key default gen_random_uuid(),
  team text not null
);
create trigger bs_rt_alias after insert on public.bs_rt_alias
  for each row execute function better_supabase.broadcast_topic('org:{org=team}', 'changed');

insert into public.bs_rt_alias (team) values ('red');

select is(
  (select payload -> 'values' from realtime.messages where topic = 'org:red'),
  '{"org": "red"}'::jsonb,
  'a {name=column} placeholder fills the topic and names the value'
);

create table public.bs_rt_pairs (
  a int not null,
  b int not null,
  primary key (a, b)
);
create trigger bs_rt_pairs after insert on public.bs_rt_pairs
  for each row execute function better_supabase.broadcast_topic('pair:{a}', 'changed');

insert into public.bs_rt_pairs (a, b) values (1, 2);

select is(
  (select payload -> 'id' from realtime.messages where topic = 'pair:1'),
  '{"a": 1, "b": 2}'::jsonb,
  'a composite primary key is sent as an object'
);

create table public.bs_rt_statement (id int primary key);
create trigger bs_rt_statement after insert on public.bs_rt_statement
  for each statement execute function better_supabase.broadcast_topic('statement', '');

select throws_ok(
  $$insert into public.bs_rt_statement (id) values (1)$$,
  '39P01',
  null,
  'broadcast_topic() refuses to run as a statement trigger'
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
