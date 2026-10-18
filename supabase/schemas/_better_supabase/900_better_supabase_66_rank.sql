-- better-supabase module: rank (0.8.0)
-- @bs-module rank@1 managed
-- Fractional rank keys: rank_between, move() for every config.subjects entry with a rank column (through the caller's policies and any state-machine trigger), and a rebalance job.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Fractional rank keys (ADR 0021). Keys are base-62 text compared with
-- collate "C"; the steps match rankBetween in better-supabase/blocks/rank.
create or replace function "better_supabase"."rank_between"(previous text, next text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_alphabet constant text := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  v_low text := coalesce(rank_between.previous, '');
  v_key text := '';
  v_bounded boolean := rank_between.next is not null;
  v_index integer := 1;
  v_low_digit integer;
  v_high_digit integer;
begin
  if rank_between.previous is not null and rank_between.previous !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'RANK_KEY_INVALID';
  end if;
  if rank_between.next is not null and rank_between.next !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'RANK_KEY_INVALID';
  end if;
  if rank_between.previous is not null and rank_between.next is not null
    and rank_between.previous collate "C" >= rank_between.next collate "C" then
    raise exception 'previous must sort before next' using errcode = '22023', hint = 'RANK_KEY_ORDER';
  end if;
  loop
    v_low_digit := case when v_index <= length(v_low) then strpos(v_alphabet, substr(v_low, v_index, 1)) - 1 else 0 end;
    v_high_digit := case
      when not v_bounded then 62
      when v_index <= length(rank_between.next) then strpos(v_alphabet, substr(rank_between.next, v_index, 1)) - 1
      else 0
    end;
    if v_high_digit = v_low_digit then
      v_key := v_key || substr(v_alphabet, v_low_digit + 1, 1);
    elsif v_high_digit - v_low_digit > 1 then
      return v_key || substr(v_alphabet, (v_low_digit + v_high_digit) / 2 + 1, 1);
    elsif v_bounded and v_index < length(rank_between.next) then
      return v_key || substr(rank_between.next, v_index, 1);
    else
      v_key := v_key || substr(v_alphabet, v_low_digit + 1, 1);
      v_bounded := false;
    end if;
    v_index := v_index + 1;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."rank_between"(text, text) from public, anon;
grant execute on function "better_supabase"."rank_between"(text, text) to authenticated, service_role;

-- Key number nth of total, spread evenly at one width (rankKeys).
create or replace function "better_supabase"."rank_key"(nth bigint, total bigint)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_alphabet constant text := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  v_width integer := 1;
  v_value numeric;
  v_key text := '';
begin
  if rank_key.nth < 1 or rank_key.nth > rank_key.total then
    raise exception 'nth must be between 1 and total' using errcode = '22023', hint = 'RANK_KEY_POSITION';
  end if;
  while 62::numeric ^ v_width <= rank_key.total loop
    v_width := v_width + 1;
  end loop;
  v_value := floor(62::numeric ^ v_width / (rank_key.total + 1)) * rank_key.nth;
  for v_place in 1..v_width loop
    v_key := substr(v_alphabet, (v_value % 62)::integer + 1, 1) || v_key;
    v_value := floor(v_value / 62);
  end loop;
  return rtrim(v_key, '0');
end;
$$;
revoke execute on function "better_supabase"."rank_key"(bigint, bigint) from public, anon;
grant execute on function "better_supabase"."rank_key"(bigint, bigint) to authenticated, service_role;

-- Moves a subject between two neighbours (either may be null for an end),
-- into to_group when given. It runs as the caller: the table's policies
-- decide what it can read and update, and a state-machine trigger on the
-- group column checks the stage change. Returns the new key.
create or replace function "better_supabase"."move"(subject_type text, subject_id text, previous_id text, next_id text, to_group text)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_tenant text;
  v_group text;
  v_other_tenant text;
  v_other_group text;
  v_previous text;
  v_next text;
  v_key text;
begin
  if not "better_supabase"."can_subject"(move.subject_type, move.subject_id, 'write') then
    raise exception 'not allowed to move this row' using errcode = '42501', hint = 'RANK_FORBIDDEN';
  end if;
  raise exception 'this subject type has no rank column in config.subjects' using errcode = '22023', hint = 'RANK_SUBJECT_UNKNOWN';
  if length(v_key) > 24 then
    perform "better_supabase"."enqueue_job"(queue => 'rank.rebalance', payload => jsonb_build_object('subjectType', move.subject_type, 'tenant', v_tenant, 'group', v_group), dedupe_key => 'rank:' || move.subject_type || ':' || coalesce(v_tenant, '') || ':' || coalesce(v_group, ''), dedupe_running => false);
  end if;
  return v_key;
end;
$$;
revoke execute on function "better_supabase"."move"(text, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."move"(text, text, text, text, text) to authenticated, service_role;

-- Rewrites every key of a tenant's rows (in rank_group, or every group) to
-- short, evenly spaced keys in the same order. Returns the rows rewritten.
create or replace function "better_supabase"."rebalance_ranks"(subject_type text, tenant text, rank_group text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
begin
  raise exception 'this subject type has no rank column in config.subjects' using errcode = '22023', hint = 'RANK_SUBJECT_UNKNOWN';
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."rebalance_ranks"(text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."rebalance_ranks"(text, text, text) to service_role;

-- blocks.rank.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."rank_between"(previous text, next text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rank_between"($1, $2) $$;
revoke execute on function "api"."rank_between"(text, text) from public, anon;
grant execute on function "api"."rank_between"(text, text) to authenticated, service_role;

create or replace function "api"."rank_key"(nth bigint, total bigint)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rank_key"($1, $2) $$;
revoke execute on function "api"."rank_key"(bigint, bigint) from public, anon;
grant execute on function "api"."rank_key"(bigint, bigint) to authenticated, service_role;

create or replace function "api"."move"(subject_type text, subject_id text, previous_id text, next_id text, to_group text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."move"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."move"(text, text, text, text, text) from public, anon;
grant execute on function "api"."move"(text, text, text, text, text) to authenticated, service_role;

create or replace function "api"."rebalance_ranks"(subject_type text, tenant text, rank_group text)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rebalance_ranks"($1, $2, $3) $$;
revoke execute on function "api"."rebalance_ranks"(text, text, text) from public, anon, authenticated;
grant execute on function "api"."rebalance_ranks"(text, text, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;
