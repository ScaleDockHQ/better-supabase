-- ==== alone: schema supabase/schemas/900_better_supabase_057_numbering.sql
-- better-supabase module: numbering
-- @bsb-block numbering@1 managed
-- @bsb-hash sha256:f8356ff1b785084b7f8c6f4726ed38824dcb0d88636e40e371996392919fa068
-- Gapless numbers per tenant, entity and period. next_number locks the row in the caller's transaction, and a trigger fills the document column so a separate round trip cannot open a gap.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."number_sequences";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Gapless numbers. next_number locks the sequence row inside the caller's
-- transaction, so a rollback releases the number. Clients get a number
-- only through a trigger: the function is service-only.
create table if not exists "better_supabase"."number_sequences" (
  "tenant_id" uuid not null,
  "entity" text not null,
  -- The legal entity (its id as text) the series belongs to; '' is the default entity.
  "scope" text not null default '',
  "period" text not null default '',
  "last_number" bigint not null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  primary key ("tenant_id", "entity", "scope", "period")
);
alter table "better_supabase"."number_sequences" enable row level security;
revoke all on "better_supabase"."number_sequences" from public, anon, authenticated;
grant all on "better_supabase"."number_sequences" to service_role;

create or replace function better_supabase.format_assigned_number(template text, n bigint, at timestamptz)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v text := template;
  width text[];
begin
  v := replace(v, '{yyyy}', to_char(at at time zone 'utc', 'YYYY'));
  v := replace(v, '{yy}', to_char(at at time zone 'utc', 'YY'));
  v := replace(v, '{mm}', to_char(at at time zone 'utc', 'MM'));
  v := replace(v, '{dd}', to_char(at at time zone 'utc', 'DD'));
  while v ~ '\{n:[0-9]+\}' loop
    width := regexp_match(v, '\{n:([0-9]+)\}');
    v := regexp_replace(v, '\{n:[0-9]+\}', lpad(n::text, width[1]::int, '0'));
  end loop;
  return replace(v, '{n}', n::text);
end;
$$;
revoke execute on function better_supabase.format_assigned_number(text, bigint, timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.format_assigned_number(text, bigint, timestamptz) to service_role;

create or replace function better_supabase.number_at(value timestamptz)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value $$;
create or replace function better_supabase.number_at(value timestamp)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value at time zone 'utc' $$;
create or replace function better_supabase.number_at(value date)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value::timestamp at time zone 'utc' $$;
revoke execute on function better_supabase.number_at(timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.number_at(timestamptz) to service_role;
revoke execute on function better_supabase.number_at(timestamp) from public, anon, authenticated;
grant execute on function better_supabase.number_at(timestamp) to service_role;
revoke execute on function better_supabase.number_at(date) from public, anon, authenticated;
grant execute on function better_supabase.number_at(date) to service_role;

create or replace function better_supabase.number_format_period(p_format text, p_at timestamptz)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_format ~ '\{yy(yy)?\}' and p_format ~ '\{mm\}' then to_char(p_at at time zone 'utc', 'YYYY-MM')
    when p_format ~ '\{yy(yy)?\}' then to_char(p_at at time zone 'utc', 'YYYY')
    else ''
  end
$$;
revoke execute on function better_supabase.number_format_period(text, timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.number_format_period(text, timestamptz) to service_role;

create or replace function better_supabase.number_period_kind(p_period text, p_format text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_period <> 'format' then p_period
    when p_format ~ '\{yy(yy)?\}' and p_format ~ '\{mm\}' then 'month'
    when p_format ~ '\{yy(yy)?\}' then 'year'
    else 'none'
  end
$$;
revoke execute on function better_supabase.number_period_kind(text, text) from public, anon, authenticated;
grant execute on function better_supabase.number_period_kind(text, text) to service_role;

create or replace function better_supabase.number_format_pattern(p_format text)
returns text
language sql
immutable
set search_path = ''
as $$
  select '^' || replace(replace(replace(
    regexp_replace(
      regexp_replace(
        replace(replace(replace(replace(p_format, '{yyyy}', chr(1)), '{yy}', chr(2)), '{mm}', chr(2)), '{dd}', chr(2)),
        '\{n(:[0-9]+)?\}', chr(3), 'g'),
      '([^[:alnum:]\x01-\x03])', '\\\1', 'g'),
    chr(1), '[0-9]{4}'), chr(2), '[0-9]{2}'), chr(3), '([0-9]+)') || '$'
$$;
revoke execute on function better_supabase.number_format_pattern(text) from public, anon, authenticated;
grant execute on function better_supabase.number_format_pattern(text) to service_role;

-- PostgreSQL refuses CREATE OR REPLACE when an argument is renamed.
drop function if exists "better_supabase"."next_number"(uuid, text, timestamptz) cascade;
drop function if exists "better_supabase"."next_number"(uuid, text, timestamptz, text) cascade;
create or replace function "better_supabase"."next_number"(tenant uuid, p_entity text, at timestamptz default now(), p_scope text default '')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text;
  v_n bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_period := '';
  if v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_number_assign"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using next_number.tenant, p_entity, v_period;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(next_number.tenant::text || ':' || p_entity || ':' || coalesce(p_scope, '') || ':' || v_period, 0));
  insert into "better_supabase"."number_sequences" ("tenant_id", "entity", "scope", "period", "last_number")
  values (next_number.tenant, p_entity, coalesce(p_scope, ''), v_period, 1)
  on conflict ("tenant_id", "entity", "scope", "period")
  do update set "last_number" = "better_supabase"."number_sequences"."last_number" + 1, "updated_at" = now()
  returning "last_number" into v_n;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_number_assign"(uuid, text, bigint)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::bigint)', v_hook::oid::regproc)
        using next_number.tenant, p_entity, v_n;
    end if;
  end;
  return v_n;
end;
$$;
revoke execute on function "better_supabase"."next_number"(uuid, text, timestamptz, text) from public, anon, authenticated;
grant execute on function "better_supabase"."next_number"(uuid, text, timestamptz, text) to service_role;

-- The series scope of a legal entity: the empty text for the default entity.
create or replace function "better_supabase"."number_scope"(p_tenant uuid, p_legal_entity uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_legal_entity is null then
    return '';
  end if;
  return p_legal_entity::text;
end;
$$;
revoke execute on function "better_supabase"."number_scope"(uuid, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."number_scope"(uuid, uuid) to service_role;

-- Takes a historical number as is. Only an import (better_supabase.import_run()
-- is set) may do it; anything else gets NUMBER_FIXED_FORBIDDEN. Raises the
-- counter of the entity, scope and period to the number when it matches the
-- current format and returns the number's sequence part. A number in another
-- format is kept: it returns the digits it ends with and sync_number_sequences
-- lists it.
create or replace function "better_supabase"."register_fixed_number"(p_tenant uuid, p_entity text, p_number text, p_at timestamptz default now(), p_scope text default '')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_format text;
  v_period text;
  v_parts text[];
  v_n bigint;
begin
  if better_supabase.import_run() is null then
    raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
  end if;
  if nullif(btrim(p_number), '') is null or length(p_number) > 200 then
    raise exception 'a fixed number is 1 to 200 characters' using errcode = '22023', hint = 'NUMBER_FIXED_INVALID';
  end if;
  v_format := null;
  v_period := '';
  if v_format is null or v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  v_parts := regexp_match(p_number, better_supabase.number_format_pattern(v_format));
  if v_parts is null or v_parts[1] is null or length(v_parts[1]) > 18 then
    return case
      when p_number ~ '[0-9]{1,18}$' then substring(p_number from '([0-9]{1,18})$')::bigint
      else 0
    end;
  end if;
  v_n := v_parts[1]::bigint;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant::text || ':' || p_entity || ':' || coalesce(p_scope, '') || ':' || v_period, 0));
  insert into "better_supabase"."number_sequences" ("tenant_id", "entity", "scope", "period", "last_number")
  values (p_tenant, p_entity, coalesce(p_scope, ''), v_period, v_n)
  on conflict ("tenant_id", "entity", "scope", "period")
  do update set "last_number" = greatest("better_supabase"."number_sequences"."last_number", excluded."last_number"), "updated_at" = now();
  return v_n;
end;
$$;
revoke execute on function "better_supabase"."register_fixed_number"(uuid, text, text, timestamptz, text) from public, anon, authenticated;
grant execute on function "better_supabase"."register_fixed_number"(uuid, text, text, timestamptz, text) to service_role;

-- Names the number the next document of an entity takes, for the entities
-- that have no argument for it (quotes, orders, cases and the rest). Import
-- mode only; the creating function uses the number once and clears it.
create or replace function "better_supabase"."set_fixed_number"(p_entity text, p_number text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if better_supabase.import_run() is null then
    raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
  end if;
  if nullif(btrim(p_entity), '') is null or nullif(btrim(p_number), '') is null then
    raise exception 'name the entity and its number' using errcode = '22023', hint = 'NUMBER_FIXED_INVALID';
  end if;
  perform set_config('better_supabase.fixed_number', p_entity || chr(31) || p_number, true);
end;
$$;
revoke execute on function "better_supabase"."set_fixed_number"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."set_fixed_number"(text, text) to service_role;

create or replace function "better_supabase"."number_format"(p_tenant uuid, p_entity text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_format text;
begin
  v_format := null;
  return v_format;
end;
$$;
revoke execute on function "better_supabase"."number_format"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."number_format"(uuid, text) to service_role;

create or replace function "better_supabase"."number_period"(p_tenant uuid, p_entity text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_period text;
begin
  v_period := null;
  if v_period is not null and v_period not in ('none', 'year', 'month', 'format') then
    raise exception 'the tenant''s number period must be none, year, month or format' using errcode = '22023', hint = 'NUMBER_PERIOD_INVALID';
  end if;
  return v_period;
end;
$$;
revoke execute on function "better_supabase"."number_period"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."number_period"(uuid, text) to service_role;

drop function if exists "better_supabase"."preview_number"(uuid, text, timestamptz);
create or replace function "better_supabase"."preview_number"(p_tenant uuid, p_entity text, p_at timestamptz default now(), p_scope text default '')
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_format text;
  v_period text;
  v_last bigint;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', p_tenant, 'numbering.assign'), false)) then
    raise exception 'not allowed to number documents in this tenant' using errcode = '42501', hint = 'NUMBER_FORBIDDEN';
  end if;
  v_format := '{n}';
  v_period := '';
  if v_format is null or v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  select s."last_number" into v_last
  from "better_supabase"."number_sequences" s
  where s."tenant_id" = p_tenant
    and s."entity" = p_entity
    and s."scope" = coalesce(p_scope, '')
    and s."period" = v_period;
  return better_supabase.format_assigned_number(v_format, coalesce(v_last, 0) + 1, p_at);
end;
$$;
revoke execute on function "better_supabase"."preview_number"(uuid, text, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."preview_number"(uuid, text, timestamptz, text) to authenticated, service_role;

-- Raises each sequence to the highest number its table already holds, per
-- tenant, scope (legal entity) and period, for rows numbered outside
-- next_number: seeds, imports and restores. A null tenant, entity or scope
-- syncs every one. Returns { synced, mismatched }: the numbers that don't
-- match the current format are listed (and added to the import run as
-- warnings), never rejected.
drop function if exists "better_supabase"."sync_number_sequences"(uuid, text);
create or replace function "better_supabase"."sync_number_sequences"(p_tenant uuid default null, p_entity text default null, p_scope text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows integer := 0;
  v_count integer;
  v_bad jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if p_entity is not null and not (false) then
    raise exception 'no numbered table for this sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;

  return jsonb_build_object('synced', v_rows, 'mismatched', v_bad);
end;
$$;
revoke execute on function "better_supabase"."sync_number_sequences"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."sync_number_sequences"(uuid, text, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_057_numbering.sql
-- better-supabase module: numbering
-- @bsb-block-data numbering
-- @bsb-hash sha256:a66767a6e66d7ecf17d8a2fc5db1a3382c51337c245be2005a35a304ae3d1155
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('numbering', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_057_numbering.sql
-- better-supabase module: numbering
-- @bsb-block numbering@1 managed
-- @bsb-hash sha256:b83b43475c126670cd0ef70a0376247c366ac8f0491744ba6908bb912880b86b
-- Gapless numbers per tenant, entity and period. next_number locks the row in the caller's transaction, and a trigger fills the document column so a separate round trip cannot open a gap.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."number_sequences";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Gapless numbers. next_number locks the sequence row inside the caller's
-- transaction, so a rollback releases the number. Clients get a number
-- only through a trigger: the function is service-only.
create table if not exists "better_supabase"."number_sequences" (
  "tenant_id" uuid not null,
  "entity" text not null,
  -- The legal entity (its id as text) the series belongs to; '' is the default entity.
  "scope" text not null default '',
  "period" text not null default '',
  "last_number" bigint not null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  primary key ("tenant_id", "entity", "scope", "period")
);
alter table "better_supabase"."number_sequences" enable row level security;
revoke all on "better_supabase"."number_sequences" from public, anon, authenticated;
grant all on "better_supabase"."number_sequences" to service_role;

create or replace function better_supabase.format_assigned_number(template text, n bigint, at timestamptz)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v text := template;
  width text[];
begin
  v := replace(v, '{yyyy}', to_char(at at time zone 'utc', 'YYYY'));
  v := replace(v, '{yy}', to_char(at at time zone 'utc', 'YY'));
  v := replace(v, '{mm}', to_char(at at time zone 'utc', 'MM'));
  v := replace(v, '{dd}', to_char(at at time zone 'utc', 'DD'));
  while v ~ '\{n:[0-9]+\}' loop
    width := regexp_match(v, '\{n:([0-9]+)\}');
    v := regexp_replace(v, '\{n:[0-9]+\}', lpad(n::text, width[1]::int, '0'));
  end loop;
  return replace(v, '{n}', n::text);
end;
$$;
revoke execute on function better_supabase.format_assigned_number(text, bigint, timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.format_assigned_number(text, bigint, timestamptz) to service_role;

create or replace function better_supabase.number_at(value timestamptz)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value $$;
create or replace function better_supabase.number_at(value timestamp)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value at time zone 'utc' $$;
create or replace function better_supabase.number_at(value date)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value::timestamp at time zone 'utc' $$;
revoke execute on function better_supabase.number_at(timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.number_at(timestamptz) to service_role;
revoke execute on function better_supabase.number_at(timestamp) from public, anon, authenticated;
grant execute on function better_supabase.number_at(timestamp) to service_role;
revoke execute on function better_supabase.number_at(date) from public, anon, authenticated;
grant execute on function better_supabase.number_at(date) to service_role;

create or replace function better_supabase.number_format_period(p_format text, p_at timestamptz)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_format ~ '\{yy(yy)?\}' and p_format ~ '\{mm\}' then to_char(p_at at time zone 'utc', 'YYYY-MM')
    when p_format ~ '\{yy(yy)?\}' then to_char(p_at at time zone 'utc', 'YYYY')
    else ''
  end
$$;
revoke execute on function better_supabase.number_format_period(text, timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.number_format_period(text, timestamptz) to service_role;

create or replace function better_supabase.number_period_kind(p_period text, p_format text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_period <> 'format' then p_period
    when p_format ~ '\{yy(yy)?\}' and p_format ~ '\{mm\}' then 'month'
    when p_format ~ '\{yy(yy)?\}' then 'year'
    else 'none'
  end
$$;
revoke execute on function better_supabase.number_period_kind(text, text) from public, anon, authenticated;
grant execute on function better_supabase.number_period_kind(text, text) to service_role;

create or replace function better_supabase.number_format_pattern(p_format text)
returns text
language sql
immutable
set search_path = ''
as $$
  select '^' || replace(replace(replace(
    regexp_replace(
      regexp_replace(
        replace(replace(replace(replace(p_format, '{yyyy}', chr(1)), '{yy}', chr(2)), '{mm}', chr(2)), '{dd}', chr(2)),
        '\{n(:[0-9]+)?\}', chr(3), 'g'),
      '([^[:alnum:]\x01-\x03])', '\\\1', 'g'),
    chr(1), '[0-9]{4}'), chr(2), '[0-9]{2}'), chr(3), '([0-9]+)') || '$'
$$;
revoke execute on function better_supabase.number_format_pattern(text) from public, anon, authenticated;
grant execute on function better_supabase.number_format_pattern(text) to service_role;

-- PostgreSQL refuses CREATE OR REPLACE when an argument is renamed.
drop function if exists "better_supabase"."next_number"(uuid, text, timestamptz) cascade;
drop function if exists "better_supabase"."next_number"(uuid, text, timestamptz, text) cascade;
create or replace function "better_supabase"."next_number"(tenant uuid, p_entity text, at timestamptz default now(), p_scope text default '')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text;
  v_n bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_period := case p_entity
    when 'donation_receipt' then ''
    when 'risk' then ''
    when 'case' then to_char(next_number.at at time zone 'utc', 'YYYY')
    when 'inspection' then to_char(next_number.at at time zone 'utc', 'YYYY')
    when 'production_order' then to_char(next_number.at at time zone 'utc', 'YYYY')
    else null
  end;
  if v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_number_assign"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using next_number.tenant, p_entity, v_period;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(next_number.tenant::text || ':' || p_entity || ':' || coalesce(p_scope, '') || ':' || v_period, 0));
  insert into "better_supabase"."number_sequences" ("tenant_id", "entity", "scope", "period", "last_number")
  values (next_number.tenant, p_entity, coalesce(p_scope, ''), v_period, 1)
  on conflict ("tenant_id", "entity", "scope", "period")
  do update set "last_number" = "better_supabase"."number_sequences"."last_number" + 1, "updated_at" = now()
  returning "last_number" into v_n;
  perform "better_supabase".emit_event('number.assigned', jsonb_build_object('organizationId', next_number.tenant, 'entity', p_entity, 'period', v_period, 'number', v_n), 'number-sequences/' || p_entity, (next_number.tenant)::text, null, 'better-supabase/numbering');
  perform better_supabase.audit_event(
    event_type => 'number.assigned',
    category => 'data',
    target_type => 'number_sequence',
    record_id => p_entity,
    summary => 'assigned ' || v_n::text,
    tenant => (next_number.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', next_number.tenant, 'entity', p_entity, 'period', v_period, 'number', v_n)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_number_assign"(uuid, text, bigint)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::bigint)', v_hook::oid::regproc)
        using next_number.tenant, p_entity, v_n;
    end if;
  end;
  return v_n;
end;
$$;
revoke execute on function "better_supabase"."next_number"(uuid, text, timestamptz, text) from public, anon, authenticated;
grant execute on function "better_supabase"."next_number"(uuid, text, timestamptz, text) to service_role;

-- The series scope of a legal entity: the empty text for the default entity.
create or replace function "better_supabase"."number_scope"(p_tenant uuid, p_legal_entity uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_legal_entity is null then
    return '';
  end if;
  if exists (
    select 1 from "better_supabase"."legal_entities" e
    where e."tenant_id" = p_tenant
      and e."id" = p_legal_entity
      and e."is_default"
  ) then
    return '';
  end if;
  return p_legal_entity::text;
end;
$$;
revoke execute on function "better_supabase"."number_scope"(uuid, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."number_scope"(uuid, uuid) to service_role;

-- Takes a historical number as is. Only an import (better_supabase.import_run()
-- is set) may do it; anything else gets NUMBER_FIXED_FORBIDDEN. Raises the
-- counter of the entity, scope and period to the number when it matches the
-- current format and returns the number's sequence part. A number in another
-- format is kept: it returns the digits it ends with and sync_number_sequences
-- lists it.
create or replace function "better_supabase"."register_fixed_number"(p_tenant uuid, p_entity text, p_number text, p_at timestamptz default now(), p_scope text default '')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_format text;
  v_period text;
  v_parts text[];
  v_n bigint;
begin
  if better_supabase.import_run() is null then
    raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
  end if;
  if nullif(btrim(p_number), '') is null or length(p_number) > 200 then
    raise exception 'a fixed number is 1 to 200 characters' using errcode = '22023', hint = 'NUMBER_FIXED_INVALID';
  end if;
  v_format := "better_supabase"."number_format"(p_tenant, p_entity);
  v_period := case p_entity
    when 'donation_receipt' then ''
    when 'risk' then ''
    when 'case' then to_char(p_at at time zone 'utc', 'YYYY')
    when 'inspection' then to_char(p_at at time zone 'utc', 'YYYY')
    when 'production_order' then to_char(p_at at time zone 'utc', 'YYYY')
    else null
  end;
  if v_format is null or v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  v_parts := regexp_match(p_number, better_supabase.number_format_pattern(v_format));
  if v_parts is null or v_parts[1] is null or length(v_parts[1]) > 18 then
    return case
      when p_number ~ '[0-9]{1,18}$' then substring(p_number from '([0-9]{1,18})$')::bigint
      else 0
    end;
  end if;
  v_n := v_parts[1]::bigint;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant::text || ':' || p_entity || ':' || coalesce(p_scope, '') || ':' || v_period, 0));
  insert into "better_supabase"."number_sequences" ("tenant_id", "entity", "scope", "period", "last_number")
  values (p_tenant, p_entity, coalesce(p_scope, ''), v_period, v_n)
  on conflict ("tenant_id", "entity", "scope", "period")
  do update set "last_number" = greatest("better_supabase"."number_sequences"."last_number", excluded."last_number"), "updated_at" = now();
  return v_n;
end;
$$;
revoke execute on function "better_supabase"."register_fixed_number"(uuid, text, text, timestamptz, text) from public, anon, authenticated;
grant execute on function "better_supabase"."register_fixed_number"(uuid, text, text, timestamptz, text) to service_role;

-- Names the number the next document of an entity takes, for the entities
-- that have no argument for it (quotes, orders, cases and the rest). Import
-- mode only; the creating function uses the number once and clears it.
create or replace function "better_supabase"."set_fixed_number"(p_entity text, p_number text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if better_supabase.import_run() is null then
    raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
  end if;
  if nullif(btrim(p_entity), '') is null or nullif(btrim(p_number), '') is null then
    raise exception 'name the entity and its number' using errcode = '22023', hint = 'NUMBER_FIXED_INVALID';
  end if;
  perform set_config('better_supabase.fixed_number', p_entity || chr(31) || p_number, true);
end;
$$;
revoke execute on function "better_supabase"."set_fixed_number"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."set_fixed_number"(text, text) to service_role;

create or replace function "better_supabase"."number_format"(p_tenant uuid, p_entity text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_format text;
begin
  v_format := case p_entity
    when 'donation_receipt' then 'R-{n}'
    when 'risk' then 'RSK-{n:4}'
    when 'case' then '{yyyy}-{n:4}'
    when 'inspection' then 'AUD-{yyyy}-{n:3}'
    when 'production_order' then 'MO-{yyyy}-{n:4}'
    else null
  end;
  return v_format;
end;
$$;
revoke execute on function "better_supabase"."number_format"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."number_format"(uuid, text) to service_role;

create or replace function "better_supabase"."number_period"(p_tenant uuid, p_entity text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_period text;
begin
  v_period := null;
  if v_period is not null and v_period not in ('none', 'year', 'month', 'format') then
    raise exception 'the tenant''s number period must be none, year, month or format' using errcode = '22023', hint = 'NUMBER_PERIOD_INVALID';
  end if;
  return v_period;
end;
$$;
revoke execute on function "better_supabase"."number_period"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."number_period"(uuid, text) to service_role;

drop function if exists "better_supabase"."preview_number"(uuid, text, timestamptz);
create or replace function "better_supabase"."preview_number"(p_tenant uuid, p_entity text, p_at timestamptz default now(), p_scope text default '')
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_format text;
  v_period text;
  v_last bigint;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', p_tenant, 'numbering.assign'), false)) then
    raise exception 'not allowed to number documents in this tenant' using errcode = '42501', hint = 'NUMBER_FORBIDDEN';
  end if;
  v_format := "better_supabase"."number_format"(p_tenant, p_entity);
  v_period := case p_entity
    when 'donation_receipt' then ''
    when 'risk' then ''
    when 'case' then to_char(p_at at time zone 'utc', 'YYYY')
    when 'inspection' then to_char(p_at at time zone 'utc', 'YYYY')
    when 'production_order' then to_char(p_at at time zone 'utc', 'YYYY')
    else null
  end;
  if v_format is null or v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  select s."last_number" into v_last
  from "better_supabase"."number_sequences" s
  where s."tenant_id" = p_tenant
    and s."entity" = p_entity
    and s."scope" = coalesce(p_scope, '')
    and s."period" = v_period;
  return better_supabase.format_assigned_number(v_format, coalesce(v_last, 0) + 1, p_at);
end;
$$;
revoke execute on function "better_supabase"."preview_number"(uuid, text, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."preview_number"(uuid, text, timestamptz, text) to authenticated, service_role;

-- Raises each sequence to the highest number its table already holds, per
-- tenant, scope (legal entity) and period, for rows numbered outside
-- next_number: seeds, imports and restores. A null tenant, entity or scope
-- syncs every one. Returns { synced, mismatched }: the numbers that don't
-- match the current format are listed (and added to the import run as
-- warnings), never rejected.
drop function if exists "better_supabase"."sync_number_sequences"(uuid, text);
create or replace function "better_supabase"."sync_number_sequences"(p_tenant uuid default null, p_entity text default null, p_scope text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows integer := 0;
  v_count integer;
  v_bad jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if p_entity is not null and not (false) then
    raise exception 'no numbered table for this sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;

  if better_supabase.import_run() is not null and jsonb_array_length(v_bad) > 0 then
    update "better_supabase"."import_runs" r
    set "errors" = r."errors" || (
      select jsonb_agg(jsonb_build_object('entity', b ->> 'entity', 'key', b ->> 'number', 'code', 'NUMBER_FORMAT_MISMATCH', 'severity', 'warning', 'message', 'the number does not match the current format of ' || (b ->> 'entity')))
      from jsonb_array_elements(v_bad) b
    )
    where r."id" = better_supabase.import_run();
  end if;
  return jsonb_build_object('synced', v_rows, 'mismatched', v_bad);
end;
$$;
revoke execute on function "better_supabase"."sync_number_sequences"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."sync_number_sequences"(uuid, text, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_057_numbering.sql
-- better-supabase module: numbering
-- @bsb-block-data numbering
-- @bsb-hash sha256:a66767a6e66d7ecf17d8a2fc5db1a3382c51337c245be2005a35a304ae3d1155
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('numbering', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_057_numbering.sql
-- better-supabase module: numbering
-- @bsb-block numbering@1 managed
-- @bsb-hash sha256:69df6962235ee8c8b39ca7c388c51df21c609112e98600fa92f6ec38bdcc1e32
-- Gapless numbers per tenant, entity and period. next_number locks the row in the caller's transaction, and a trigger fills the document column so a separate round trip cannot open a gap.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."number_sequences";
    drop policy if exists bsb_tenant_scope_select on "app_private"."number_sequences";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."number_sequences";
    drop policy if exists bsb_tenant_scope_update on "app_private"."number_sequences";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."number_sequences";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Gapless numbers. next_number locks the sequence row inside the caller's
-- transaction, so a rollback releases the number. Clients get a number
-- only through a trigger: the function is service-only.
create table if not exists "app_private"."number_sequences" (
  "tenant_id" uuid not null,
  "entity" text not null,
  -- The legal entity (its id as text) the series belongs to; '' is the default entity.
  "scope" text not null default '',
  "period" text not null default '',
  "last_number" bigint not null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  primary key ("tenant_id", "entity", "scope", "period")
);
alter table "app_private"."number_sequences" enable row level security;
revoke all on "app_private"."number_sequences" from public, anon, authenticated;
grant all on "app_private"."number_sequences" to service_role;

create or replace function better_supabase.format_assigned_number(template text, n bigint, at timestamptz)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v text := template;
  width text[];
begin
  v := replace(v, '{yyyy}', to_char(at at time zone 'utc', 'YYYY'));
  v := replace(v, '{yy}', to_char(at at time zone 'utc', 'YY'));
  v := replace(v, '{mm}', to_char(at at time zone 'utc', 'MM'));
  v := replace(v, '{dd}', to_char(at at time zone 'utc', 'DD'));
  while v ~ '\{n:[0-9]+\}' loop
    width := regexp_match(v, '\{n:([0-9]+)\}');
    v := regexp_replace(v, '\{n:[0-9]+\}', lpad(n::text, width[1]::int, '0'));
  end loop;
  return replace(v, '{n}', n::text);
end;
$$;
revoke execute on function better_supabase.format_assigned_number(text, bigint, timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.format_assigned_number(text, bigint, timestamptz) to service_role;

create or replace function better_supabase.number_at(value timestamptz)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value $$;
create or replace function better_supabase.number_at(value timestamp)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value at time zone 'utc' $$;
create or replace function better_supabase.number_at(value date)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value::timestamp at time zone 'utc' $$;
revoke execute on function better_supabase.number_at(timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.number_at(timestamptz) to service_role;
revoke execute on function better_supabase.number_at(timestamp) from public, anon, authenticated;
grant execute on function better_supabase.number_at(timestamp) to service_role;
revoke execute on function better_supabase.number_at(date) from public, anon, authenticated;
grant execute on function better_supabase.number_at(date) to service_role;

create or replace function better_supabase.number_format_period(p_format text, p_at timestamptz)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_format ~ '\{yy(yy)?\}' and p_format ~ '\{mm\}' then to_char(p_at at time zone 'utc', 'YYYY-MM')
    when p_format ~ '\{yy(yy)?\}' then to_char(p_at at time zone 'utc', 'YYYY')
    else ''
  end
$$;
revoke execute on function better_supabase.number_format_period(text, timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.number_format_period(text, timestamptz) to service_role;

create or replace function better_supabase.number_period_kind(p_period text, p_format text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_period <> 'format' then p_period
    when p_format ~ '\{yy(yy)?\}' and p_format ~ '\{mm\}' then 'month'
    when p_format ~ '\{yy(yy)?\}' then 'year'
    else 'none'
  end
$$;
revoke execute on function better_supabase.number_period_kind(text, text) from public, anon, authenticated;
grant execute on function better_supabase.number_period_kind(text, text) to service_role;

create or replace function better_supabase.number_format_pattern(p_format text)
returns text
language sql
immutable
set search_path = ''
as $$
  select '^' || replace(replace(replace(
    regexp_replace(
      regexp_replace(
        replace(replace(replace(replace(p_format, '{yyyy}', chr(1)), '{yy}', chr(2)), '{mm}', chr(2)), '{dd}', chr(2)),
        '\{n(:[0-9]+)?\}', chr(3), 'g'),
      '([^[:alnum:]\x01-\x03])', '\\\1', 'g'),
    chr(1), '[0-9]{4}'), chr(2), '[0-9]{2}'), chr(3), '([0-9]+)') || '$'
$$;
revoke execute on function better_supabase.number_format_pattern(text) from public, anon, authenticated;
grant execute on function better_supabase.number_format_pattern(text) to service_role;

-- PostgreSQL refuses CREATE OR REPLACE when an argument is renamed.
drop function if exists "app_private"."next_number"(uuid, text, timestamptz) cascade;
drop function if exists "app_private"."next_number"(uuid, text, timestamptz, text) cascade;
create or replace function "app_private"."next_number"(tenant uuid, p_entity text, at timestamptz default now(), p_scope text default '')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text;
  v_n bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_period := '';
  if v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_number_assign"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using next_number.tenant, p_entity, v_period;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(next_number.tenant::text || ':' || p_entity || ':' || coalesce(p_scope, '') || ':' || v_period, 0));
  insert into "app_private"."number_sequences" ("tenant_id", "entity", "scope", "period", "last_number")
  values (next_number.tenant, p_entity, coalesce(p_scope, ''), v_period, 1)
  on conflict ("tenant_id", "entity", "scope", "period")
  do update set "last_number" = "app_private"."number_sequences"."last_number" + 1, "updated_at" = now()
  returning "last_number" into v_n;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_number_assign"(uuid, text, bigint)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::bigint)', v_hook::oid::regproc)
        using next_number.tenant, p_entity, v_n;
    end if;
  end;
  return v_n;
end;
$$;
revoke execute on function "app_private"."next_number"(uuid, text, timestamptz, text) from public, anon, authenticated;
grant execute on function "app_private"."next_number"(uuid, text, timestamptz, text) to service_role;

-- The series scope of a legal entity: the empty text for the default entity.
create or replace function "app_private"."number_scope"(p_tenant uuid, p_legal_entity uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_legal_entity is null then
    return '';
  end if;
  return p_legal_entity::text;
end;
$$;
revoke execute on function "app_private"."number_scope"(uuid, uuid) from public, anon, authenticated;
grant execute on function "app_private"."number_scope"(uuid, uuid) to service_role;

-- Takes a historical number as is. Only an import (better_supabase.import_run()
-- is set) may do it; anything else gets NUMBER_FIXED_FORBIDDEN. Raises the
-- counter of the entity, scope and period to the number when it matches the
-- current format and returns the number's sequence part. A number in another
-- format is kept: it returns the digits it ends with and sync_number_sequences
-- lists it.
create or replace function "app_private"."register_fixed_number"(p_tenant uuid, p_entity text, p_number text, p_at timestamptz default now(), p_scope text default '')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_format text;
  v_period text;
  v_parts text[];
  v_n bigint;
begin
  if better_supabase.import_run() is null then
    raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
  end if;
  if nullif(btrim(p_number), '') is null or length(p_number) > 200 then
    raise exception 'a fixed number is 1 to 200 characters' using errcode = '22023', hint = 'NUMBER_FIXED_INVALID';
  end if;
  v_format := null;
  v_period := '';
  if v_format is null or v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  v_parts := regexp_match(p_number, better_supabase.number_format_pattern(v_format));
  if v_parts is null or v_parts[1] is null or length(v_parts[1]) > 18 then
    return case
      when p_number ~ '[0-9]{1,18}$' then substring(p_number from '([0-9]{1,18})$')::bigint
      else 0
    end;
  end if;
  v_n := v_parts[1]::bigint;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant::text || ':' || p_entity || ':' || coalesce(p_scope, '') || ':' || v_period, 0));
  insert into "app_private"."number_sequences" ("tenant_id", "entity", "scope", "period", "last_number")
  values (p_tenant, p_entity, coalesce(p_scope, ''), v_period, v_n)
  on conflict ("tenant_id", "entity", "scope", "period")
  do update set "last_number" = greatest("app_private"."number_sequences"."last_number", excluded."last_number"), "updated_at" = now();
  return v_n;
end;
$$;
revoke execute on function "app_private"."register_fixed_number"(uuid, text, text, timestamptz, text) from public, anon, authenticated;
grant execute on function "app_private"."register_fixed_number"(uuid, text, text, timestamptz, text) to service_role;

-- Names the number the next document of an entity takes, for the entities
-- that have no argument for it (quotes, orders, cases and the rest). Import
-- mode only; the creating function uses the number once and clears it.
create or replace function "app_private"."set_fixed_number"(p_entity text, p_number text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if better_supabase.import_run() is null then
    raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
  end if;
  if nullif(btrim(p_entity), '') is null or nullif(btrim(p_number), '') is null then
    raise exception 'name the entity and its number' using errcode = '22023', hint = 'NUMBER_FIXED_INVALID';
  end if;
  perform set_config('better_supabase.fixed_number', p_entity || chr(31) || p_number, true);
end;
$$;
revoke execute on function "app_private"."set_fixed_number"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."set_fixed_number"(text, text) to service_role;

create or replace function "app_private"."number_format"(p_tenant uuid, p_entity text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_format text;
begin
  v_format := null;
  return v_format;
end;
$$;
revoke execute on function "app_private"."number_format"(uuid, text) from public, anon, authenticated;
grant execute on function "app_private"."number_format"(uuid, text) to service_role;

create or replace function "app_private"."number_period"(p_tenant uuid, p_entity text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_period text;
begin
  v_period := null;
  if v_period is not null and v_period not in ('none', 'year', 'month', 'format') then
    raise exception 'the tenant''s number period must be none, year, month or format' using errcode = '22023', hint = 'NUMBER_PERIOD_INVALID';
  end if;
  return v_period;
end;
$$;
revoke execute on function "app_private"."number_period"(uuid, text) from public, anon, authenticated;
grant execute on function "app_private"."number_period"(uuid, text) to service_role;

drop function if exists "app_private"."preview_number"(uuid, text, timestamptz);
create or replace function "app_private"."preview_number"(p_tenant uuid, p_entity text, p_at timestamptz default now(), p_scope text default '')
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_format text;
  v_period text;
  v_last bigint;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', p_tenant, 'numbering.assign'), false)) then
    raise exception 'not allowed to number documents in this tenant' using errcode = '42501', hint = 'NUMBER_FORBIDDEN';
  end if;
  v_format := '{n}';
  v_period := '';
  if v_format is null or v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  select s."last_number" into v_last
  from "app_private"."number_sequences" s
  where s."tenant_id" = p_tenant
    and s."entity" = p_entity
    and s."scope" = coalesce(p_scope, '')
    and s."period" = v_period;
  return better_supabase.format_assigned_number(v_format, coalesce(v_last, 0) + 1, p_at);
end;
$$;
revoke execute on function "app_private"."preview_number"(uuid, text, timestamptz, text) from public, anon;
grant execute on function "app_private"."preview_number"(uuid, text, timestamptz, text) to authenticated, service_role;

-- Raises each sequence to the highest number its table already holds, per
-- tenant, scope (legal entity) and period, for rows numbered outside
-- next_number: seeds, imports and restores. A null tenant, entity or scope
-- syncs every one. Returns { synced, mismatched }: the numbers that don't
-- match the current format are listed (and added to the import run as
-- warnings), never rejected.
drop function if exists "app_private"."sync_number_sequences"(uuid, text);
create or replace function "app_private"."sync_number_sequences"(p_tenant uuid default null, p_entity text default null, p_scope text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows integer := 0;
  v_count integer;
  v_bad jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if p_entity is not null and not (false) then
    raise exception 'no numbered table for this sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;

  return jsonb_build_object('synced', v_rows, 'mismatched', v_bad);
end;
$$;
revoke execute on function "app_private"."sync_number_sequences"(uuid, text, text) from public, anon, authenticated;
grant execute on function "app_private"."sync_number_sequences"(uuid, text, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_057_numbering.sql
-- better-supabase module: numbering
-- @bsb-block-data numbering
-- @bsb-hash sha256:a66767a6e66d7ecf17d8a2fc5db1a3382c51337c245be2005a35a304ae3d1155
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('numbering', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_057_numbering.sql
-- better-supabase module: numbering
-- @bsb-block numbering@1 managed
-- @bsb-hash sha256:c8dadd1793be493c1545f001637df0f59684074bda4fc72d0e8e350cbd0d227d
-- Gapless numbers per tenant, entity and period. next_number locks the row in the caller's transaction, and a trigger fills the document column so a separate round trip cannot open a gap.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."number_sequences";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Gapless numbers. next_number locks the sequence row inside the caller's
-- transaction, so a rollback releases the number. Clients get a number
-- only through a trigger: the function is service-only.
create table if not exists "better_supabase"."number_sequences" (
  "tenant_id" uuid not null,
  "entity" text not null,
  -- The legal entity (its id as text) the series belongs to; '' is the default entity.
  "scope" text not null default '',
  "period" text not null default '',
  "last_number" bigint not null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  primary key ("tenant_id", "entity", "scope", "period")
);
alter table "better_supabase"."number_sequences" enable row level security;
revoke all on "better_supabase"."number_sequences" from public, anon, authenticated;
grant all on "better_supabase"."number_sequences" to service_role;

create or replace function better_supabase.format_assigned_number(template text, n bigint, at timestamptz)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v text := template;
  width text[];
begin
  v := replace(v, '{yyyy}', to_char(at at time zone 'utc', 'YYYY'));
  v := replace(v, '{yy}', to_char(at at time zone 'utc', 'YY'));
  v := replace(v, '{mm}', to_char(at at time zone 'utc', 'MM'));
  v := replace(v, '{dd}', to_char(at at time zone 'utc', 'DD'));
  while v ~ '\{n:[0-9]+\}' loop
    width := regexp_match(v, '\{n:([0-9]+)\}');
    v := regexp_replace(v, '\{n:[0-9]+\}', lpad(n::text, width[1]::int, '0'));
  end loop;
  return replace(v, '{n}', n::text);
end;
$$;
revoke execute on function better_supabase.format_assigned_number(text, bigint, timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.format_assigned_number(text, bigint, timestamptz) to service_role;

create or replace function better_supabase.number_at(value timestamptz)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value $$;
create or replace function better_supabase.number_at(value timestamp)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value at time zone 'utc' $$;
create or replace function better_supabase.number_at(value date)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value::timestamp at time zone 'utc' $$;
revoke execute on function better_supabase.number_at(timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.number_at(timestamptz) to service_role;
revoke execute on function better_supabase.number_at(timestamp) from public, anon, authenticated;
grant execute on function better_supabase.number_at(timestamp) to service_role;
revoke execute on function better_supabase.number_at(date) from public, anon, authenticated;
grant execute on function better_supabase.number_at(date) to service_role;

create or replace function better_supabase.number_format_period(p_format text, p_at timestamptz)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_format ~ '\{yy(yy)?\}' and p_format ~ '\{mm\}' then to_char(p_at at time zone 'utc', 'YYYY-MM')
    when p_format ~ '\{yy(yy)?\}' then to_char(p_at at time zone 'utc', 'YYYY')
    else ''
  end
$$;
revoke execute on function better_supabase.number_format_period(text, timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.number_format_period(text, timestamptz) to service_role;

create or replace function better_supabase.number_period_kind(p_period text, p_format text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_period <> 'format' then p_period
    when p_format ~ '\{yy(yy)?\}' and p_format ~ '\{mm\}' then 'month'
    when p_format ~ '\{yy(yy)?\}' then 'year'
    else 'none'
  end
$$;
revoke execute on function better_supabase.number_period_kind(text, text) from public, anon, authenticated;
grant execute on function better_supabase.number_period_kind(text, text) to service_role;

create or replace function better_supabase.number_format_pattern(p_format text)
returns text
language sql
immutable
set search_path = ''
as $$
  select '^' || replace(replace(replace(
    regexp_replace(
      regexp_replace(
        replace(replace(replace(replace(p_format, '{yyyy}', chr(1)), '{yy}', chr(2)), '{mm}', chr(2)), '{dd}', chr(2)),
        '\{n(:[0-9]+)?\}', chr(3), 'g'),
      '([^[:alnum:]\x01-\x03])', '\\\1', 'g'),
    chr(1), '[0-9]{4}'), chr(2), '[0-9]{2}'), chr(3), '([0-9]+)') || '$'
$$;
revoke execute on function better_supabase.number_format_pattern(text) from public, anon, authenticated;
grant execute on function better_supabase.number_format_pattern(text) to service_role;

-- PostgreSQL refuses CREATE OR REPLACE when an argument is renamed.
drop function if exists "better_supabase"."next_number"(uuid, text, timestamptz) cascade;
drop function if exists "better_supabase"."next_number"(uuid, text, timestamptz, text) cascade;
create or replace function "better_supabase"."next_number"(tenant uuid, p_entity text, at timestamptz default now(), p_scope text default '')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text;
  v_n bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_period := '';
  if v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_number_assign"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using next_number.tenant, p_entity, v_period;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(next_number.tenant::text || ':' || p_entity || ':' || coalesce(p_scope, '') || ':' || v_period, 0));
  insert into "better_supabase"."number_sequences" ("tenant_id", "entity", "scope", "period", "last_number")
  values (next_number.tenant, p_entity, coalesce(p_scope, ''), v_period, 1)
  on conflict ("tenant_id", "entity", "scope", "period")
  do update set "last_number" = "better_supabase"."number_sequences"."last_number" + 1, "updated_at" = now()
  returning "last_number" into v_n;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_number_assign"(uuid, text, bigint)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::bigint)', v_hook::oid::regproc)
        using next_number.tenant, p_entity, v_n;
    end if;
  end;
  return v_n;
end;
$$;
revoke execute on function "better_supabase"."next_number"(uuid, text, timestamptz, text) from public, anon, authenticated;
grant execute on function "better_supabase"."next_number"(uuid, text, timestamptz, text) to service_role;

-- The series scope of a legal entity: the empty text for the default entity.
create or replace function "better_supabase"."number_scope"(p_tenant uuid, p_legal_entity uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_legal_entity is null then
    return '';
  end if;
  return p_legal_entity::text;
end;
$$;
revoke execute on function "better_supabase"."number_scope"(uuid, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."number_scope"(uuid, uuid) to service_role;

-- Takes a historical number as is. Only an import (better_supabase.import_run()
-- is set) may do it; anything else gets NUMBER_FIXED_FORBIDDEN. Raises the
-- counter of the entity, scope and period to the number when it matches the
-- current format and returns the number's sequence part. A number in another
-- format is kept: it returns the digits it ends with and sync_number_sequences
-- lists it.
create or replace function "better_supabase"."register_fixed_number"(p_tenant uuid, p_entity text, p_number text, p_at timestamptz default now(), p_scope text default '')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_format text;
  v_period text;
  v_parts text[];
  v_n bigint;
begin
  if better_supabase.import_run() is null then
    raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
  end if;
  if nullif(btrim(p_number), '') is null or length(p_number) > 200 then
    raise exception 'a fixed number is 1 to 200 characters' using errcode = '22023', hint = 'NUMBER_FIXED_INVALID';
  end if;
  v_format := null;
  v_period := '';
  if v_format is null or v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  v_parts := regexp_match(p_number, better_supabase.number_format_pattern(v_format));
  if v_parts is null or v_parts[1] is null or length(v_parts[1]) > 18 then
    return case
      when p_number ~ '[0-9]{1,18}$' then substring(p_number from '([0-9]{1,18})$')::bigint
      else 0
    end;
  end if;
  v_n := v_parts[1]::bigint;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant::text || ':' || p_entity || ':' || coalesce(p_scope, '') || ':' || v_period, 0));
  insert into "better_supabase"."number_sequences" ("tenant_id", "entity", "scope", "period", "last_number")
  values (p_tenant, p_entity, coalesce(p_scope, ''), v_period, v_n)
  on conflict ("tenant_id", "entity", "scope", "period")
  do update set "last_number" = greatest("better_supabase"."number_sequences"."last_number", excluded."last_number"), "updated_at" = now();
  return v_n;
end;
$$;
revoke execute on function "better_supabase"."register_fixed_number"(uuid, text, text, timestamptz, text) from public, anon, authenticated;
grant execute on function "better_supabase"."register_fixed_number"(uuid, text, text, timestamptz, text) to service_role;

-- Names the number the next document of an entity takes, for the entities
-- that have no argument for it (quotes, orders, cases and the rest). Import
-- mode only; the creating function uses the number once and clears it.
create or replace function "better_supabase"."set_fixed_number"(p_entity text, p_number text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if better_supabase.import_run() is null then
    raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
  end if;
  if nullif(btrim(p_entity), '') is null or nullif(btrim(p_number), '') is null then
    raise exception 'name the entity and its number' using errcode = '22023', hint = 'NUMBER_FIXED_INVALID';
  end if;
  perform set_config('better_supabase.fixed_number', p_entity || chr(31) || p_number, true);
end;
$$;
revoke execute on function "better_supabase"."set_fixed_number"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."set_fixed_number"(text, text) to service_role;

create or replace function "better_supabase"."number_format"(p_tenant uuid, p_entity text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_format text;
begin
  v_format := null;
  return v_format;
end;
$$;
revoke execute on function "better_supabase"."number_format"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."number_format"(uuid, text) to service_role;

create or replace function "better_supabase"."number_period"(p_tenant uuid, p_entity text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_period text;
begin
  v_period := null;
  if v_period is not null and v_period not in ('none', 'year', 'month', 'format') then
    raise exception 'the tenant''s number period must be none, year, month or format' using errcode = '22023', hint = 'NUMBER_PERIOD_INVALID';
  end if;
  return v_period;
end;
$$;
revoke execute on function "better_supabase"."number_period"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."number_period"(uuid, text) to service_role;

drop function if exists "better_supabase"."preview_number"(uuid, text, timestamptz);
create or replace function "better_supabase"."preview_number"(p_tenant uuid, p_entity text, p_at timestamptz default now(), p_scope text default '')
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_format text;
  v_period text;
  v_last bigint;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', p_tenant, 'numbering.assign'), false)) then
    raise exception 'not allowed to number documents in this tenant' using errcode = '42501', hint = 'NUMBER_FORBIDDEN';
  end if;
  v_format := '{n}';
  v_period := '';
  if v_format is null or v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  select s."last_number" into v_last
  from "better_supabase"."number_sequences" s
  where s."tenant_id" = p_tenant
    and s."entity" = p_entity
    and s."scope" = coalesce(p_scope, '')
    and s."period" = v_period;
  return better_supabase.format_assigned_number(v_format, coalesce(v_last, 0) + 1, p_at);
end;
$$;
revoke execute on function "better_supabase"."preview_number"(uuid, text, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."preview_number"(uuid, text, timestamptz, text) to authenticated, service_role;

-- Raises each sequence to the highest number its table already holds, per
-- tenant, scope (legal entity) and period, for rows numbered outside
-- next_number: seeds, imports and restores. A null tenant, entity or scope
-- syncs every one. Returns { synced, mismatched }: the numbers that don't
-- match the current format are listed (and added to the import run as
-- warnings), never rejected.
drop function if exists "better_supabase"."sync_number_sequences"(uuid, text);
create or replace function "better_supabase"."sync_number_sequences"(p_tenant uuid default null, p_entity text default null, p_scope text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows integer := 0;
  v_count integer;
  v_bad jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if p_entity is not null and not (false) then
    raise exception 'no numbered table for this sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;

  return jsonb_build_object('synced', v_rows, 'mismatched', v_bad);
end;
$$;
revoke execute on function "better_supabase"."sync_number_sequences"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."sync_number_sequences"(uuid, text, text) to service_role;

-- blocks.numbering.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."preview_number"(uuid, text, timestamptz);
drop function if exists "api"."sync_number_sequences"(uuid, text);

create or replace function "api"."import_run"()
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_run"() $$;
revoke execute on function "api"."import_run"() from public;
grant execute on function "api"."import_run"() to anon, authenticated, service_role;

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."format_assigned_number"(template text, n bigint, at timestamptz)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."format_assigned_number"($1, $2, $3) $$;
revoke execute on function "api"."format_assigned_number"(text, bigint, timestamptz) from public, anon, authenticated;
grant execute on function "api"."format_assigned_number"(text, bigint, timestamptz) to service_role;

create or replace function "api"."number_at"(value timestamptz)
returns timestamptz
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."number_at"($1) $$;
revoke execute on function "api"."number_at"(timestamptz) from public, anon, authenticated;
grant execute on function "api"."number_at"(timestamptz) to service_role;

create or replace function "api"."number_at"(value timestamp)
returns timestamptz
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."number_at"($1) $$;
revoke execute on function "api"."number_at"(timestamp) from public, anon, authenticated;
grant execute on function "api"."number_at"(timestamp) to service_role;

create or replace function "api"."number_at"(value date)
returns timestamptz
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."number_at"($1) $$;
revoke execute on function "api"."number_at"(date) from public, anon, authenticated;
grant execute on function "api"."number_at"(date) to service_role;

create or replace function "api"."number_format_period"(p_format text, p_at timestamptz)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."number_format_period"($1, $2) $$;
revoke execute on function "api"."number_format_period"(text, timestamptz) from public, anon, authenticated;
grant execute on function "api"."number_format_period"(text, timestamptz) to service_role;

create or replace function "api"."number_period_kind"(p_period text, p_format text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."number_period_kind"($1, $2) $$;
revoke execute on function "api"."number_period_kind"(text, text) from public, anon, authenticated;
grant execute on function "api"."number_period_kind"(text, text) to service_role;

create or replace function "api"."number_format_pattern"(p_format text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."number_format_pattern"($1) $$;
revoke execute on function "api"."number_format_pattern"(text) from public, anon, authenticated;
grant execute on function "api"."number_format_pattern"(text) to service_role;

create or replace function "api"."next_number"(tenant uuid, p_entity text, at timestamptz default now(), p_scope text default '')
returns bigint
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."next_number"($1, $2, $3, $4) $$;
revoke execute on function "api"."next_number"(uuid, text, timestamptz, text) from public, anon, authenticated;
grant execute on function "api"."next_number"(uuid, text, timestamptz, text) to service_role;

create or replace function "api"."number_scope"(p_tenant uuid, p_legal_entity uuid)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."number_scope"($1, $2) $$;
revoke execute on function "api"."number_scope"(uuid, uuid) from public, anon, authenticated;
grant execute on function "api"."number_scope"(uuid, uuid) to service_role;

create or replace function "api"."register_fixed_number"(p_tenant uuid, p_entity text, p_number text, p_at timestamptz default now(), p_scope text default '')
returns bigint
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."register_fixed_number"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."register_fixed_number"(uuid, text, text, timestamptz, text) from public, anon, authenticated;
grant execute on function "api"."register_fixed_number"(uuid, text, text, timestamptz, text) to service_role;

create or replace function "api"."set_fixed_number"(p_entity text, p_number text)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_fixed_number"($1, $2) $$;
revoke execute on function "api"."set_fixed_number"(text, text) from public, anon, authenticated;
grant execute on function "api"."set_fixed_number"(text, text) to service_role;

create or replace function "api"."number_format"(p_tenant uuid, p_entity text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."number_format"($1, $2) $$;
revoke execute on function "api"."number_format"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."number_format"(uuid, text) to service_role;

create or replace function "api"."number_period"(p_tenant uuid, p_entity text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."number_period"($1, $2) $$;
revoke execute on function "api"."number_period"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."number_period"(uuid, text) to service_role;

create or replace function "api"."preview_number"(p_tenant uuid, p_entity text, p_at timestamptz default now(), p_scope text default '')
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."preview_number"($1, $2, $3, $4) $$;
revoke execute on function "api"."preview_number"(uuid, text, timestamptz, text) from public, anon;
grant execute on function "api"."preview_number"(uuid, text, timestamptz, text) to authenticated, service_role;

create or replace function "api"."sync_number_sequences"(p_tenant uuid default null, p_entity text default null, p_scope text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."sync_number_sequences"($1, $2, $3) $$;
revoke execute on function "api"."sync_number_sequences"(uuid, text, text) from public, anon, authenticated;
grant execute on function "api"."sync_number_sequences"(uuid, text, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_057_numbering.sql
-- better-supabase module: numbering
-- @bsb-block-data numbering
-- @bsb-hash sha256:a66767a6e66d7ecf17d8a2fc5db1a3382c51337c245be2005a35a304ae3d1155
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('numbering', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_057_numbering.sql
-- better-supabase module: numbering
-- @bsb-block numbering@1 managed
-- @bsb-hash sha256:e45a5884071fd600ad85310a57e4d6c3127cbce4a378f36bb790d6960ede59bc
-- Gapless numbers per tenant, entity and period. next_number locks the row in the caller's transaction, and a trigger fills the document column so a separate round trip cannot open a gap.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."number_sequences";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Gapless numbers. next_number locks the sequence row inside the caller's
-- transaction, so a rollback releases the number. Clients get a number
-- only through a trigger: the function is service-only.
-- better_supabase.number_sequences is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."number_sequences" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."number_sequences" add column if not exists "entity" text;
alter table "better_supabase"."number_sequences" add column if not exists "scope" text not null default '';
alter table "better_supabase"."number_sequences" add column if not exists "period" text not null default '';
alter table "better_supabase"."number_sequences" add column if not exists "last_number" bigint;
alter table "better_supabase"."number_sequences" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."number_sequences" add column if not exists "updated_at" timestamptz not null default now();
alter table "better_supabase"."number_sequences" enable row level security;
grant all on "better_supabase"."number_sequences" to service_role;
do $$
declare
  v_constraint record;
begin
  for v_constraint in
    select c.conname
    from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."number_sequences"'::pg_catalog.regclass
      and c.contype in ('p', 'u')
      and not exists (
        select 1
        from pg_catalog.pg_attribute a
        where a.attrelid = c.conrelid
          and a.attnum = any (c.conkey)
          and a.attname = 'scope'
      )
  loop
    execute pg_catalog.format('alter table "better_supabase"."number_sequences" drop constraint %I', v_constraint.conname);
  end loop;
end
$$;
create unique index if not exists number_sequences_series_key on "better_supabase"."number_sequences" ("tenant_id", "entity", "scope", "period");

create or replace function better_supabase.format_assigned_number(template text, n bigint, at timestamptz)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v text := template;
  width text[];
begin
  v := replace(v, '{yyyy}', to_char(at at time zone 'utc', 'YYYY'));
  v := replace(v, '{yy}', to_char(at at time zone 'utc', 'YY'));
  v := replace(v, '{mm}', to_char(at at time zone 'utc', 'MM'));
  v := replace(v, '{dd}', to_char(at at time zone 'utc', 'DD'));
  while v ~ '\{n:[0-9]+\}' loop
    width := regexp_match(v, '\{n:([0-9]+)\}');
    v := regexp_replace(v, '\{n:[0-9]+\}', lpad(n::text, width[1]::int, '0'));
  end loop;
  return replace(v, '{n}', n::text);
end;
$$;
revoke execute on function better_supabase.format_assigned_number(text, bigint, timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.format_assigned_number(text, bigint, timestamptz) to service_role;

create or replace function better_supabase.number_at(value timestamptz)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value $$;
create or replace function better_supabase.number_at(value timestamp)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value at time zone 'utc' $$;
create or replace function better_supabase.number_at(value date)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value::timestamp at time zone 'utc' $$;
revoke execute on function better_supabase.number_at(timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.number_at(timestamptz) to service_role;
revoke execute on function better_supabase.number_at(timestamp) from public, anon, authenticated;
grant execute on function better_supabase.number_at(timestamp) to service_role;
revoke execute on function better_supabase.number_at(date) from public, anon, authenticated;
grant execute on function better_supabase.number_at(date) to service_role;

create or replace function better_supabase.number_format_period(p_format text, p_at timestamptz)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_format ~ '\{yy(yy)?\}' and p_format ~ '\{mm\}' then to_char(p_at at time zone 'utc', 'YYYY-MM')
    when p_format ~ '\{yy(yy)?\}' then to_char(p_at at time zone 'utc', 'YYYY')
    else ''
  end
$$;
revoke execute on function better_supabase.number_format_period(text, timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.number_format_period(text, timestamptz) to service_role;

create or replace function better_supabase.number_period_kind(p_period text, p_format text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_period <> 'format' then p_period
    when p_format ~ '\{yy(yy)?\}' and p_format ~ '\{mm\}' then 'month'
    when p_format ~ '\{yy(yy)?\}' then 'year'
    else 'none'
  end
$$;
revoke execute on function better_supabase.number_period_kind(text, text) from public, anon, authenticated;
grant execute on function better_supabase.number_period_kind(text, text) to service_role;

create or replace function better_supabase.number_format_pattern(p_format text)
returns text
language sql
immutable
set search_path = ''
as $$
  select '^' || replace(replace(replace(
    regexp_replace(
      regexp_replace(
        replace(replace(replace(replace(p_format, '{yyyy}', chr(1)), '{yy}', chr(2)), '{mm}', chr(2)), '{dd}', chr(2)),
        '\{n(:[0-9]+)?\}', chr(3), 'g'),
      '([^[:alnum:]\x01-\x03])', '\\\1', 'g'),
    chr(1), '[0-9]{4}'), chr(2), '[0-9]{2}'), chr(3), '([0-9]+)') || '$'
$$;
revoke execute on function better_supabase.number_format_pattern(text) from public, anon, authenticated;
grant execute on function better_supabase.number_format_pattern(text) to service_role;

-- PostgreSQL refuses CREATE OR REPLACE when an argument is renamed.
drop function if exists "better_supabase"."next_number"(uuid, text, timestamptz) cascade;
drop function if exists "better_supabase"."next_number"(uuid, text, timestamptz, text) cascade;
create or replace function "better_supabase"."next_number"(tenant uuid, p_entity text, at timestamptz default now(), p_scope text default '')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text;
  v_n bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_period := '';
  if v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_number_assign"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using next_number.tenant, p_entity, v_period;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(next_number.tenant::text || ':' || p_entity || ':' || coalesce(p_scope, '') || ':' || v_period, 0));
  insert into "better_supabase"."number_sequences" ("tenant_id", "entity", "scope", "period", "last_number")
  values (next_number.tenant, better_supabase.as_column_type(p_entity, (null::"better_supabase"."number_sequences")."entity"), coalesce(p_scope, ''), v_period, 1)
  on conflict ("tenant_id", "entity", "scope", "period")
  do update set "last_number" = "better_supabase"."number_sequences"."last_number" + 1, "updated_at" = now()
  returning "last_number" into v_n;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_number_assign"(uuid, text, bigint)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::bigint)', v_hook::oid::regproc)
        using next_number.tenant, p_entity, v_n;
    end if;
  end;
  return v_n;
end;
$$;
revoke execute on function "better_supabase"."next_number"(uuid, text, timestamptz, text) from public, anon, authenticated;
grant execute on function "better_supabase"."next_number"(uuid, text, timestamptz, text) to service_role;

-- The series scope of a legal entity: the empty text for the default entity.
create or replace function "better_supabase"."number_scope"(p_tenant uuid, p_legal_entity uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_legal_entity is null then
    return '';
  end if;
  return p_legal_entity::text;
end;
$$;
revoke execute on function "better_supabase"."number_scope"(uuid, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."number_scope"(uuid, uuid) to service_role;

-- Takes a historical number as is. Only an import (better_supabase.import_run()
-- is set) may do it; anything else gets NUMBER_FIXED_FORBIDDEN. Raises the
-- counter of the entity, scope and period to the number when it matches the
-- current format and returns the number's sequence part. A number in another
-- format is kept: it returns the digits it ends with and sync_number_sequences
-- lists it.
create or replace function "better_supabase"."register_fixed_number"(p_tenant uuid, p_entity text, p_number text, p_at timestamptz default now(), p_scope text default '')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_format text;
  v_period text;
  v_parts text[];
  v_n bigint;
begin
  if better_supabase.import_run() is null then
    raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
  end if;
  if nullif(btrim(p_number), '') is null or length(p_number) > 200 then
    raise exception 'a fixed number is 1 to 200 characters' using errcode = '22023', hint = 'NUMBER_FIXED_INVALID';
  end if;
  v_format := null;
  v_period := '';
  if v_format is null or v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  v_parts := regexp_match(p_number, better_supabase.number_format_pattern(v_format));
  if v_parts is null or v_parts[1] is null or length(v_parts[1]) > 18 then
    return case
      when p_number ~ '[0-9]{1,18}$' then substring(p_number from '([0-9]{1,18})$')::bigint
      else 0
    end;
  end if;
  v_n := v_parts[1]::bigint;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant::text || ':' || p_entity || ':' || coalesce(p_scope, '') || ':' || v_period, 0));
  insert into "better_supabase"."number_sequences" ("tenant_id", "entity", "scope", "period", "last_number")
  values (p_tenant, better_supabase.as_column_type(p_entity, (null::"better_supabase"."number_sequences")."entity"), coalesce(p_scope, ''), v_period, v_n)
  on conflict ("tenant_id", "entity", "scope", "period")
  do update set "last_number" = greatest("better_supabase"."number_sequences"."last_number", excluded."last_number"), "updated_at" = now();
  return v_n;
end;
$$;
revoke execute on function "better_supabase"."register_fixed_number"(uuid, text, text, timestamptz, text) from public, anon, authenticated;
grant execute on function "better_supabase"."register_fixed_number"(uuid, text, text, timestamptz, text) to service_role;

-- Names the number the next document of an entity takes, for the entities
-- that have no argument for it (quotes, orders, cases and the rest). Import
-- mode only; the creating function uses the number once and clears it.
create or replace function "better_supabase"."set_fixed_number"(p_entity text, p_number text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if better_supabase.import_run() is null then
    raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
  end if;
  if nullif(btrim(p_entity), '') is null or nullif(btrim(p_number), '') is null then
    raise exception 'name the entity and its number' using errcode = '22023', hint = 'NUMBER_FIXED_INVALID';
  end if;
  perform set_config('better_supabase.fixed_number', p_entity || chr(31) || p_number, true);
end;
$$;
revoke execute on function "better_supabase"."set_fixed_number"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."set_fixed_number"(text, text) to service_role;

create or replace function "better_supabase"."number_format"(p_tenant uuid, p_entity text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_format text;
begin
  v_format := null;
  return v_format;
end;
$$;
revoke execute on function "better_supabase"."number_format"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."number_format"(uuid, text) to service_role;

create or replace function "better_supabase"."number_period"(p_tenant uuid, p_entity text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_period text;
begin
  v_period := null;
  if v_period is not null and v_period not in ('none', 'year', 'month', 'format') then
    raise exception 'the tenant''s number period must be none, year, month or format' using errcode = '22023', hint = 'NUMBER_PERIOD_INVALID';
  end if;
  return v_period;
end;
$$;
revoke execute on function "better_supabase"."number_period"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."number_period"(uuid, text) to service_role;

drop function if exists "better_supabase"."preview_number"(uuid, text, timestamptz);
create or replace function "better_supabase"."preview_number"(p_tenant uuid, p_entity text, p_at timestamptz default now(), p_scope text default '')
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_format text;
  v_period text;
  v_last bigint;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', p_tenant, 'numbering.assign'), false)) then
    raise exception 'not allowed to number documents in this tenant' using errcode = '42501', hint = 'NUMBER_FORBIDDEN';
  end if;
  v_format := '{n}';
  v_period := '';
  if v_format is null or v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  select s."last_number" into v_last
  from "better_supabase"."number_sequences" s
  where s."tenant_id" = p_tenant
    and s."entity" = better_supabase.as_column_type(p_entity, (null::"better_supabase"."number_sequences")."entity")
    and s."scope" = coalesce(p_scope, '')
    and s."period" = v_period;
  return better_supabase.format_assigned_number(v_format, coalesce(v_last, 0) + 1, p_at);
end;
$$;
revoke execute on function "better_supabase"."preview_number"(uuid, text, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."preview_number"(uuid, text, timestamptz, text) to authenticated, service_role;

-- Raises each sequence to the highest number its table already holds, per
-- tenant, scope (legal entity) and period, for rows numbered outside
-- next_number: seeds, imports and restores. A null tenant, entity or scope
-- syncs every one. Returns { synced, mismatched }: the numbers that don't
-- match the current format are listed (and added to the import run as
-- warnings), never rejected.
drop function if exists "better_supabase"."sync_number_sequences"(uuid, text);
create or replace function "better_supabase"."sync_number_sequences"(p_tenant uuid default null, p_entity text default null, p_scope text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows integer := 0;
  v_count integer;
  v_bad jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if p_entity is not null and not (false) then
    raise exception 'no numbered table for this sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;

  return jsonb_build_object('synced', v_rows, 'mismatched', v_bad);
end;
$$;
revoke execute on function "better_supabase"."sync_number_sequences"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."sync_number_sequences"(uuid, text, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_057_numbering.sql
-- better-supabase module: numbering
-- @bsb-block-data numbering
-- @bsb-hash sha256:a66767a6e66d7ecf17d8a2fc5db1a3382c51337c245be2005a35a304ae3d1155
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('numbering', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_057_numbering.sql
-- better-supabase module: numbering
-- @bsb-block numbering@1 managed
-- @bsb-hash sha256:5cc31a2bfc86b2e11bb036b9b84f9b0a10f0f78855761e0506e303ca6710978c
-- Gapless numbers per tenant, entity and period. next_number locks the row in the caller's transaction, and a trigger fills the document column so a separate round trip cannot open a gap.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."number_sequences";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."number_sequences";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Gapless numbers. next_number locks the sequence row inside the caller's
-- transaction, so a rollback releases the number. Clients get a number
-- only through a trigger: the function is service-only.
create table if not exists "better_supabase"."number_sequences" (
  "org_id" uuid not null,
  "entity" text not null,
  -- The legal entity (its id as text) the series belongs to; '' is the default entity.
  "scope" text not null default '',
  "period" text not null default '',
  "last_number" bigint not null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  primary key ("org_id", "entity", "scope", "period")
);
alter table "better_supabase"."number_sequences" enable row level security;
revoke all on "better_supabase"."number_sequences" from public, anon, authenticated;
grant all on "better_supabase"."number_sequences" to service_role;

create or replace function better_supabase.format_assigned_number(template text, n bigint, at timestamptz)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v text := template;
  width text[];
begin
  v := replace(v, '{yyyy}', to_char(at at time zone 'utc', 'YYYY'));
  v := replace(v, '{yy}', to_char(at at time zone 'utc', 'YY'));
  v := replace(v, '{mm}', to_char(at at time zone 'utc', 'MM'));
  v := replace(v, '{dd}', to_char(at at time zone 'utc', 'DD'));
  while v ~ '\{n:[0-9]+\}' loop
    width := regexp_match(v, '\{n:([0-9]+)\}');
    v := regexp_replace(v, '\{n:[0-9]+\}', lpad(n::text, width[1]::int, '0'));
  end loop;
  return replace(v, '{n}', n::text);
end;
$$;
revoke execute on function better_supabase.format_assigned_number(text, bigint, timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.format_assigned_number(text, bigint, timestamptz) to service_role;

create or replace function better_supabase.number_at(value timestamptz)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value $$;
create or replace function better_supabase.number_at(value timestamp)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value at time zone 'utc' $$;
create or replace function better_supabase.number_at(value date)
returns timestamptz
language sql
immutable
set search_path = ''
as $$ select value::timestamp at time zone 'utc' $$;
revoke execute on function better_supabase.number_at(timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.number_at(timestamptz) to service_role;
revoke execute on function better_supabase.number_at(timestamp) from public, anon, authenticated;
grant execute on function better_supabase.number_at(timestamp) to service_role;
revoke execute on function better_supabase.number_at(date) from public, anon, authenticated;
grant execute on function better_supabase.number_at(date) to service_role;

create or replace function better_supabase.number_format_period(p_format text, p_at timestamptz)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_format ~ '\{yy(yy)?\}' and p_format ~ '\{mm\}' then to_char(p_at at time zone 'utc', 'YYYY-MM')
    when p_format ~ '\{yy(yy)?\}' then to_char(p_at at time zone 'utc', 'YYYY')
    else ''
  end
$$;
revoke execute on function better_supabase.number_format_period(text, timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.number_format_period(text, timestamptz) to service_role;

create or replace function better_supabase.number_period_kind(p_period text, p_format text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_period <> 'format' then p_period
    when p_format ~ '\{yy(yy)?\}' and p_format ~ '\{mm\}' then 'month'
    when p_format ~ '\{yy(yy)?\}' then 'year'
    else 'none'
  end
$$;
revoke execute on function better_supabase.number_period_kind(text, text) from public, anon, authenticated;
grant execute on function better_supabase.number_period_kind(text, text) to service_role;

create or replace function better_supabase.number_format_pattern(p_format text)
returns text
language sql
immutable
set search_path = ''
as $$
  select '^' || replace(replace(replace(
    regexp_replace(
      regexp_replace(
        replace(replace(replace(replace(p_format, '{yyyy}', chr(1)), '{yy}', chr(2)), '{mm}', chr(2)), '{dd}', chr(2)),
        '\{n(:[0-9]+)?\}', chr(3), 'g'),
      '([^[:alnum:]\x01-\x03])', '\\\1', 'g'),
    chr(1), '[0-9]{4}'), chr(2), '[0-9]{2}'), chr(3), '([0-9]+)') || '$'
$$;
revoke execute on function better_supabase.number_format_pattern(text) from public, anon, authenticated;
grant execute on function better_supabase.number_format_pattern(text) to service_role;

-- PostgreSQL refuses CREATE OR REPLACE when an argument is renamed.
drop function if exists "better_supabase"."next_number"(uuid, text, timestamptz) cascade;
drop function if exists "better_supabase"."next_number"(uuid, text, timestamptz, text) cascade;
create or replace function "better_supabase"."next_number"(tenant uuid, p_entity text, at timestamptz default now(), p_scope text default '')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text;
  v_n bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_period := '';
  if v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_number_assign"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using next_number.tenant, p_entity, v_period;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(next_number.tenant::text || ':' || p_entity || ':' || coalesce(p_scope, '') || ':' || v_period, 0));
  insert into "better_supabase"."number_sequences" ("org_id", "entity", "scope", "period", "last_number")
  values (next_number.tenant, p_entity, coalesce(p_scope, ''), v_period, 1)
  on conflict ("org_id", "entity", "scope", "period")
  do update set "last_number" = "better_supabase"."number_sequences"."last_number" + 1, "updated_at" = now()
  returning "last_number" into v_n;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_number_assign"(uuid, text, bigint)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::bigint)', v_hook::oid::regproc)
        using next_number.tenant, p_entity, v_n;
    end if;
  end;
  return v_n;
end;
$$;
revoke execute on function "better_supabase"."next_number"(uuid, text, timestamptz, text) from public, anon, authenticated;
grant execute on function "better_supabase"."next_number"(uuid, text, timestamptz, text) to service_role;

-- The series scope of a legal entity: the empty text for the default entity.
create or replace function "better_supabase"."number_scope"(p_tenant uuid, p_legal_entity uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_legal_entity is null then
    return '';
  end if;
  return p_legal_entity::text;
end;
$$;
revoke execute on function "better_supabase"."number_scope"(uuid, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."number_scope"(uuid, uuid) to service_role;

-- Takes a historical number as is. Only an import (better_supabase.import_run()
-- is set) may do it; anything else gets NUMBER_FIXED_FORBIDDEN. Raises the
-- counter of the entity, scope and period to the number when it matches the
-- current format and returns the number's sequence part. A number in another
-- format is kept: it returns the digits it ends with and sync_number_sequences
-- lists it.
create or replace function "better_supabase"."register_fixed_number"(p_tenant uuid, p_entity text, p_number text, p_at timestamptz default now(), p_scope text default '')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_format text;
  v_period text;
  v_parts text[];
  v_n bigint;
begin
  if better_supabase.import_run() is null then
    raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
  end if;
  if nullif(btrim(p_number), '') is null or length(p_number) > 200 then
    raise exception 'a fixed number is 1 to 200 characters' using errcode = '22023', hint = 'NUMBER_FIXED_INVALID';
  end if;
  v_format := null;
  v_period := '';
  if v_format is null or v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  v_parts := regexp_match(p_number, better_supabase.number_format_pattern(v_format));
  if v_parts is null or v_parts[1] is null or length(v_parts[1]) > 18 then
    return case
      when p_number ~ '[0-9]{1,18}$' then substring(p_number from '([0-9]{1,18})$')::bigint
      else 0
    end;
  end if;
  v_n := v_parts[1]::bigint;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant::text || ':' || p_entity || ':' || coalesce(p_scope, '') || ':' || v_period, 0));
  insert into "better_supabase"."number_sequences" ("org_id", "entity", "scope", "period", "last_number")
  values (p_tenant, p_entity, coalesce(p_scope, ''), v_period, v_n)
  on conflict ("org_id", "entity", "scope", "period")
  do update set "last_number" = greatest("better_supabase"."number_sequences"."last_number", excluded."last_number"), "updated_at" = now();
  return v_n;
end;
$$;
revoke execute on function "better_supabase"."register_fixed_number"(uuid, text, text, timestamptz, text) from public, anon, authenticated;
grant execute on function "better_supabase"."register_fixed_number"(uuid, text, text, timestamptz, text) to service_role;

-- Names the number the next document of an entity takes, for the entities
-- that have no argument for it (quotes, orders, cases and the rest). Import
-- mode only; the creating function uses the number once and clears it.
create or replace function "better_supabase"."set_fixed_number"(p_entity text, p_number text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if better_supabase.import_run() is null then
    raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
  end if;
  if nullif(btrim(p_entity), '') is null or nullif(btrim(p_number), '') is null then
    raise exception 'name the entity and its number' using errcode = '22023', hint = 'NUMBER_FIXED_INVALID';
  end if;
  perform set_config('better_supabase.fixed_number', p_entity || chr(31) || p_number, true);
end;
$$;
revoke execute on function "better_supabase"."set_fixed_number"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."set_fixed_number"(text, text) to service_role;

create or replace function "better_supabase"."number_format"(p_tenant uuid, p_entity text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_format text;
begin
  v_format := null;
  return v_format;
end;
$$;
revoke execute on function "better_supabase"."number_format"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."number_format"(uuid, text) to service_role;

create or replace function "better_supabase"."number_period"(p_tenant uuid, p_entity text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_period text;
begin
  v_period := null;
  if v_period is not null and v_period not in ('none', 'year', 'month', 'format') then
    raise exception 'the tenant''s number period must be none, year, month or format' using errcode = '22023', hint = 'NUMBER_PERIOD_INVALID';
  end if;
  return v_period;
end;
$$;
revoke execute on function "better_supabase"."number_period"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."number_period"(uuid, text) to service_role;

drop function if exists "better_supabase"."preview_number"(uuid, text, timestamptz);
create or replace function "better_supabase"."preview_number"(p_tenant uuid, p_entity text, p_at timestamptz default now(), p_scope text default '')
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_format text;
  v_period text;
  v_last bigint;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', p_tenant, 'numbering.assign'), false)) then
    raise exception 'not allowed to number documents in this tenant' using errcode = '42501', hint = 'NUMBER_FORBIDDEN';
  end if;
  v_format := '{n}';
  v_period := '';
  if v_format is null or v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  select s."last_number" into v_last
  from "better_supabase"."number_sequences" s
  where s."org_id" = p_tenant
    and s."entity" = p_entity
    and s."scope" = coalesce(p_scope, '')
    and s."period" = v_period;
  return better_supabase.format_assigned_number(v_format, coalesce(v_last, 0) + 1, p_at);
end;
$$;
revoke execute on function "better_supabase"."preview_number"(uuid, text, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."preview_number"(uuid, text, timestamptz, text) to authenticated, service_role;

-- Raises each sequence to the highest number its table already holds, per
-- tenant, scope (legal entity) and period, for rows numbered outside
-- next_number: seeds, imports and restores. A null tenant, entity or scope
-- syncs every one. Returns { synced, mismatched }: the numbers that don't
-- match the current format are listed (and added to the import run as
-- warnings), never rejected.
drop function if exists "better_supabase"."sync_number_sequences"(uuid, text);
create or replace function "better_supabase"."sync_number_sequences"(p_tenant uuid default null, p_entity text default null, p_scope text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows integer := 0;
  v_count integer;
  v_bad jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if p_entity is not null and not (false) then
    raise exception 'no numbered table for this sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;

  return jsonb_build_object('synced', v_rows, 'mismatched', v_bad);
end;
$$;
revoke execute on function "better_supabase"."sync_number_sequences"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."sync_number_sequences"(uuid, text, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_057_numbering.sql
-- better-supabase module: numbering
-- @bsb-block-data numbering
-- @bsb-hash sha256:a66767a6e66d7ecf17d8a2fc5db1a3382c51337c245be2005a35a304ae3d1155
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('numbering', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
