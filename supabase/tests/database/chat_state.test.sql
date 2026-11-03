-- The chat-sdk-state module on the fixture: locks, values, lists and queues of
-- the Chat SDK's state adapter. Run with `supabase test db` after the fixture
-- is regenerated for chat-sdk-state version 2 (bigint TTLs).
begin;
select plan(17);

select table_privs_are('better_supabase', 'chat_state_locks', 'anon', '{}'::text[],
  'anon has no privileges on chat locks');
select table_privs_are('better_supabase', 'chat_state_cache', 'authenticated', '{}'::text[],
  'authenticated has no privileges on the chat cache');
select function_privs_are('better_supabase', 'chat_state_set', array['text', 'text', 'jsonb', 'bigint'],
  'authenticated', '{}'::text[], 'authenticated cannot call chat_state_set');

-- Locks: one holder, a token to release, a force release.
select isnt(
  better_supabase.chat_state_acquire_lock('t', 'thread-1', 'tok-a', 60000), null,
  'the first caller takes the lock');
select is(
  better_supabase.chat_state_acquire_lock('t', 'thread-1', 'tok-b', 60000), null,
  'a second caller gets nothing while it is held');
select is(
  better_supabase.chat_state_release_lock('t', 'thread-1', 'tok-b'), false,
  'a wrong token does not release the lock');
select better_supabase.chat_state_force_release_lock('t', 'thread-1');
select isnt(
  better_supabase.chat_state_acquire_lock('t', 'thread-1', 'tok-b', 60000), null,
  'a force release lets the next caller in');

-- A TTL of 30 days overflows int4 milliseconds (2,592,000,000).
select lives_ok(
  $$select better_supabase.chat_state_set('t', 'long', '"v"'::jsonb, 2592000000)$$,
  'a 30 day TTL in milliseconds is accepted');
select is(better_supabase.chat_state_get('t', 'long'), '"v"'::jsonb,
  'the value is stored under the long TTL');

-- Values and lists.
select better_supabase.chat_state_set('t', 'k', '1'::jsonb, null);
select is(better_supabase.chat_state_set_if_not_exists('t', 'k', '2'::jsonb, null), false,
  'set_if_not_exists keeps an existing value');
select better_supabase.chat_state_append_to_list('t', 'l', '1'::jsonb, 2, null);
select better_supabase.chat_state_append_to_list('t', 'l', '2'::jsonb, 2, null);
select better_supabase.chat_state_append_to_list('t', 'l', '3'::jsonb, 2, null);
select is(better_supabase.chat_state_get_list('t', 'l'), '["2", "3"]'::jsonb,
  'a list keeps the newest entries up to max_length, in order');
select better_supabase.chat_state_delete('t', 'l');
select is(jsonb_array_length(better_supabase.chat_state_get_list('t', 'l')), 0,
  'delete removes the list as well as the value');

-- Queues: first in, first out, with a depth.
select better_supabase.chat_state_enqueue('t', 'q', '"a"'::jsonb, now() + interval '1 hour', null);
select better_supabase.chat_state_enqueue('t', 'q', '"b"'::jsonb, now() + interval '1 hour', null);
select is(better_supabase.chat_state_queue_depth('t', 'q'), 2, 'the queue holds both entries');
select is(better_supabase.chat_state_dequeue('t', 'q'), '"a"'::jsonb,
  'dequeue returns the oldest entry first');

select * from finish();
rollback;
