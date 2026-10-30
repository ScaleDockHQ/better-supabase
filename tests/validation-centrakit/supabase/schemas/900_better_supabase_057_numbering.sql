-- better-supabase module: numbering
-- @bsb-block numbering@1 managed
-- @bsb-hash sha256:8c09308a5a3b7ac32fc916d48a132d1020b8a239a8f2bf07c7fabd5800d13ce0
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
    drop policy if exists bsb_tenant_scope on "centrakit"."organization_number_sequences";
    drop policy if exists bsb_tenant_scope_select on "centrakit"."organization_number_sequences";
    drop policy if exists bsb_tenant_scope_insert on "centrakit"."organization_number_sequences";
    drop policy if exists bsb_tenant_scope_update on "centrakit"."organization_number_sequences";
    drop policy if exists bsb_tenant_scope_delete on "centrakit"."organization_number_sequences";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Gapless numbers. next_number locks the sequence row inside the caller's
-- transaction, so a rollback releases the number. Clients get a number
-- only through a trigger: the function is service-only.
-- centrakit.organization_number_sequences is the app's table, and it has every column this block needs.
alter table "centrakit"."organization_number_sequences" enable row level security;
grant all on "centrakit"."organization_number_sequences" to service_role;

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
create or replace function "better_supabase"."next_number"(tenant uuid, p_entity text, at timestamptz default now())
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_period text;
  v_n bigint;
begin
  if not ((centrakit.authz_actor_may_write())) then
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
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(next_number.tenant::text || ':' || p_entity || ':' || v_period, 0));
  insert into "centrakit"."organization_number_sequences" ("tenant_id", "entity", "period", "last_number")
  values (next_number.tenant, better_supabase.as_column_type(p_entity, (null::"centrakit"."organization_number_sequences")."entity"), v_period, 1)
  on conflict ("tenant_id", "entity", "period")
  do update set "last_number" = "centrakit"."organization_number_sequences"."last_number" + 1, "updated_at" = now()
  returning "last_number" into v_n;
  perform "better_supabase".emit_event('number.assigned', jsonb_build_object('organizationId', next_number.tenant, 'entity', p_entity, 'period', v_period, 'number', v_n), 'number-sequences/' || p_entity, (next_number.tenant)::text, null, 'domain');
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
revoke execute on function "better_supabase"."next_number"(uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."next_number"(uuid, text, timestamptz) to service_role;

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

create or replace function "better_supabase"."preview_number"(p_tenant uuid, p_entity text, p_at timestamptz default now())
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
  from "centrakit"."organization_number_sequences" s
  where s."tenant_id" = p_tenant
    and s."entity" = better_supabase.as_column_type(p_entity, (null::"centrakit"."organization_number_sequences")."entity")
    and s."period" = v_period;
  return better_supabase.format_assigned_number(v_format, coalesce(v_last, 0) + 1, p_at);
end;
$$;
revoke execute on function "better_supabase"."preview_number"(uuid, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."preview_number"(uuid, text, timestamptz) to authenticated, service_role;

-- Raises each sequence to the highest number its table already holds, per
-- tenant and period, for rows numbered outside next_number: seeds, imports
-- and restores. A null tenant or entity syncs every one.
create or replace function "better_supabase"."sync_number_sequences"(p_tenant uuid default null, p_entity text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows integer := 0;
  v_count integer;
begin
  if not ((centrakit.authz_actor_may_write())) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if p_entity is not null and not (false) then
    raise exception 'no numbered table for this sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;

  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."sync_number_sequences"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."sync_number_sequences"(uuid, text) to service_role;

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
