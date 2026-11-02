-- sessions_overview() on the fixture: the caller's unexpired sessions, the
-- current one marked, and nobody else's. The admin (…00a1) holds two sessions
-- and an expired one; another member (…00a2) holds one.
begin;
select plan(5);

insert into auth.sessions (id, user_id, created_at, updated_at, not_after)
values
  ('00000000-0000-4000-8000-0000000005e1', '00000000-0000-4000-8000-0000000000a1', now() - interval '2 hours', now() - interval '1 hour', null),
  ('00000000-0000-4000-8000-0000000005e2', '00000000-0000-4000-8000-0000000000a1', now() - interval '3 hours', now() - interval '30 minutes', null),
  ('00000000-0000-4000-8000-0000000005e3', '00000000-0000-4000-8000-0000000000a1', now() - interval '9 hours', now() - interval '8 hours', now() - interval '1 hour'),
  ('00000000-0000-4000-8000-0000000005e4', '00000000-0000-4000-8000-0000000000a2', now() - interval '1 hour', now(), null);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","session_id":"00000000-0000-4000-8000-0000000005e1"}',
  true
);
set local role authenticated;

select is(
  (better_supabase.sessions_overview() ->> 'count')::int,
  2,
  'the overview counts the unexpired sessions of the caller only'
);
select is(
  better_supabase.sessions_overview() ->> 'currentId',
  '00000000-0000-4000-8000-0000000005e1',
  'the overview names the session behind the token'
);
select is(
  better_supabase.sessions_overview() -> 'sessions' -> 0 ->> 'id',
  '00000000-0000-4000-8000-0000000005e2',
  'the most recently active session comes first'
);
select is(
  better_supabase.sessions_overview() -> 'sessions' -> 1 -> 'current',
  'true'::jsonb,
  'the current session is marked'
);
select is(
  better_supabase.sessions_overview(),
  jsonb_build_object(
    'count', jsonb_array_length(better_supabase.list_my_sessions()),
    'currentId', '00000000-0000-4000-8000-0000000005e1',
    'sessions', better_supabase.list_my_sessions()),
  'the overview is the listing with the count and the current id'
);

select * from finish();
rollback;
