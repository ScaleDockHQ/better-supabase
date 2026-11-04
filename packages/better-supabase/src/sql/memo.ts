/**
 * A memo for one transaction, over a transaction-local setting. PostgREST runs
 * one request in one transaction, so a policy helper can compute a value once
 * and every later call in the statement reads it (ADR 0230). The empty string
 * reads as unset.
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
$$;`;
