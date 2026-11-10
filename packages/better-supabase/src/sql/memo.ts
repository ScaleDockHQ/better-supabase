/**
 * A memo for one transaction, over a transaction-local setting. PostgREST runs
 * one request in one transaction, so a policy helper can compute a value once
 * and every later call in the statement reads it (ADR 0230). The empty string
 * reads as unset.
 *
 * A setting a transaction sets stays in the session's table of placeholders
 * after the transaction ends, so a key that varies per statement or per user
 * would grow it for the life of a pooled connection. `memo_slot_get` and
 * `memo_slot_set` keep such a key in one of 256 settings (ADR 0644): the slot
 * holds one key and its value, and a second key in the same slot replaces it,
 * which costs a recompute and never a wrong answer. `memo_get` and `memo_set`
 * stay for the few fixed keys (a generation counter) that must not be
 * replaced.
 */
export const MEMO_FUNCTIONS = `
create or replace function better_supabase.memo_get(key text)
returns text
language sql
volatile
set search_path = ''
as $$
  select nullif(pg_catalog.current_setting('better_supabase.memo.' || key, true), '')
$$;

create or replace function better_supabase.memo_set(key text, value text)
returns text
language sql
volatile
set search_path = ''
as $$
  select pg_catalog.set_config('better_supabase.memo.' || key, value, true)
$$;

create or replace function better_supabase.memo_slot_get(key text)
returns text
language sql
volatile
set search_path = ''
as $$
  select case when pg_catalog.split_part(v.slot, pg_catalog.chr(31), 1) = key
    then nullif(pg_catalog.substr(v.slot, pg_catalog.length(key) + 2), '') end
  from (select pg_catalog.current_setting('better_supabase.memo.s' || (pg_catalog.hashtext(key) & 255)::text, true) as slot) v
$$;

create or replace function better_supabase.memo_slot_set(key text, value text)
returns text
language sql
volatile
set search_path = ''
as $$
  select pg_catalog.set_config('better_supabase.memo.s' || (pg_catalog.hashtext(key) & 255)::text, key || pg_catalog.chr(31) || coalesce(value, ''), true)
$$;`;
