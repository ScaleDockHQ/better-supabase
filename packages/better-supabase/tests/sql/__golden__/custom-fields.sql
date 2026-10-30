-- ==== alone: schema supabase/schemas/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block custom-fields@3 managed
-- @bsb-hash sha256:a7b00bc83c285668752b4c6564da39f8269569671299cffbd1dcaaf4f5080e17
-- Field definitions, options and typed values. A sensitive value is readable only with the field's permission. Inline layout stores the definition on the value row.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_definitions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_values";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function "better_supabase"."bsb_valid_bsn"(value text)
returns boolean
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select case
    when value !~ '^[0-9]{9}$' or value = '000000000' then false
    else (
      select sum(substr(value, i, 1)::integer * case when i = 9 then -1 else 10 - i end)
      from generate_series(1, 9) as i
    ) % 11 = 0
  end
$$;
revoke execute on function "better_supabase"."bsb_valid_bsn"(text) from public, anon;
grant execute on function "better_supabase"."bsb_valid_bsn"(text) to authenticated, service_role;
create or replace function "better_supabase"."bsb_valid_iban"(value text)
returns boolean
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select case
    when value !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' then false
    else (
      select string_agg(case when ascii(c.ch) between 65 and 90 then (ascii(c.ch) - 55)::text else c.ch end, '' order by c.n)
      from regexp_split_to_table(substr(value, 5) || substr(value, 1, 4), '') with ordinality as c(ch, n)
    )::numeric % 97 = 1
  end
$$;
revoke execute on function "better_supabase"."bsb_valid_iban"(text) from public, anon;
grant execute on function "better_supabase"."bsb_valid_iban"(text) to authenticated, service_role;
-- A sensitive value is returned only when the caller holds the field's
-- permission, or custom_fields.sensitive.read when the field names none.
create table if not exists "better_supabase"."field_definitions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "entity" text not null,
  "key" text not null,
  "label" text not null,
  "type" text not null,
  "required" boolean not null default false,
  "sensitive" boolean not null default false,
  "permission" text,
  "encrypted" boolean not null default false,
  "rank" text collate "C" not null default 'V',
  unique ("tenant_id", "entity", "key")
);
alter table "better_supabase"."field_definitions" drop constraint if exists "field_definitions_type_check";
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."field_definitions"'::regclass and c.conname = 'bsb_field_definitions_type'
  ), 'pg_constraint'), '') <> 'better-supabase check 068e6990' then
    alter table "better_supabase"."field_definitions" drop constraint if exists "bsb_field_definitions_type";
    alter table "better_supabase"."field_definitions" add constraint "bsb_field_definitions_type" check ("type" in ('text', 'number', 'date', 'bool', 'option', 'json', 'email', 'url', 'multi_option', 'user', 'rating', 'currency', 'bsn', 'iban', 'phone_e164'));
    comment on constraint "bsb_field_definitions_type" on "better_supabase"."field_definitions" is 'better-supabase check 068e6990';
  end if;
end;
$$;
alter table "better_supabase"."field_definitions" enable row level security;
revoke all on "better_supabase"."field_definitions" from public, anon, authenticated;
grant select on "better_supabase"."field_definitions" to authenticated;
grant all on "better_supabase"."field_definitions" to service_role;
create table if not exists "better_supabase"."field_values" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "definition_id" uuid references "better_supabase"."field_definitions" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "value_text" text,
  "value_number" numeric,
  "value_date" date,
  "value_bool" boolean,
  "option_id" uuid,
  "value_json" jsonb
  , unique ("tenant_id", "subject_type", "subject_id", "definition_id")
);
alter table "better_supabase"."field_values" enable row level security;
revoke all on "better_supabase"."field_values" from public, anon, authenticated;
grant select on "better_supabase"."field_values" to authenticated;
grant all on "better_supabase"."field_values" to service_role;
create index if not exists field_values_definition_idx on "better_supabase"."field_values" ("definition_id");

create or replace function "better_supabase"."save_field_definition"(tenant uuid, entity text, key text, label text, type text, sensitive boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_field_definition.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  select max(d."rank" collate "C") into v_last from "better_supabase"."field_definitions" d
    where d."tenant_id" = save_field_definition.tenant and d."entity" = save_field_definition.entity;
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."field_definitions" ("tenant_id", "entity", "key", "label", "type", "sensitive", "rank")
  values (save_field_definition.tenant, save_field_definition.entity, save_field_definition.key, save_field_definition.label, save_field_definition.type, coalesce(save_field_definition.sensitive, false), v_rank)
  on conflict ("tenant_id", "entity", "key")
  do update set "label" = excluded."label", "sensitive" = excluded."sensitive"
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) to authenticated, service_role;

create or replace function "better_supabase"."read_field_values"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_values jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id', v."id", 'text', v."value_text")), '[]'::jsonb)
  into v_values
  from "better_supabase"."field_values" v
  left join "better_supabase"."field_definitions" d on d."id" = v."definition_id"
  where v."tenant_id" = read_field_values.tenant
    and v."subject_type" = read_field_values.subject_type
    and v."subject_id" = read_field_values.subject_id
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', read_field_values.tenant, 'custom_fields.read'), false))
    and (not coalesce(d."sensitive", false)
        or coalesce(better_supabase.can('tenant', v."tenant_id", coalesce(d."permission", 'custom_fields.read_sensitive')), false));
  return v_values;
end;
$$;
revoke execute on function "better_supabase"."read_field_values"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."read_field_values"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."set_field_value"(tenant uuid, subject_type text, subject_id text, definition uuid, value text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_field_value.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to set custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and not (case d."type" when 'bsn' then "better_supabase"."bsb_valid_bsn"(set_field_value.value) when 'iban' then "better_supabase"."bsb_valid_iban"(set_field_value.value) when 'phone_e164' then set_field_value.value ~* '^\+[1-9][0-9]{1,14}$' else true end)) then
    raise exception 'the value doesn''t match the field''s format' using errcode = '22023', hint = 'FIELD_VALUE_INVALID';
  end if;
  insert into "better_supabase"."field_values" ("tenant_id", "definition_id", "subject_type", "subject_id", "value_text")
  values (set_field_value.tenant, set_field_value.definition, set_field_value.subject_type, set_field_value.subject_id, set_field_value.value)
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."set_field_value"(uuid, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."set_field_value"(uuid, text, text, uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_field_definition"(definition uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."field_definitions" where "id" = delete_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  delete from "better_supabase"."field_definitions" where "id" = delete_field_definition.definition;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_field_definition"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_field_definition"(uuid) to authenticated, service_role;

-- The definitions of one entity in display order.
create or replace function "better_supabase"."list_field_definitions"(tenant uuid, entity text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'rank', d."rank"
  ) order by d."rank" collate "C", d."key"), '[]'::jsonb)
  from "better_supabase"."field_definitions" d
  where d."tenant_id" = list_field_definitions.tenant
    and d."entity" = list_field_definitions.entity
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_field_definitions.tenant, 'custom_fields.read'), false))
$$;
revoke execute on function "better_supabase"."list_field_definitions"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_field_definitions"(uuid, text) to authenticated, service_role;

-- Sets a field's rank key, from rankBetween over its neighbours' keys.
create or replace function "better_supabase"."rank_field_definition"(definition uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_field_definition.rank is null or rank_field_definition.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'FIELD_RANK_INVALID';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."field_definitions" where "id" = rank_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  update "better_supabase"."field_definitions" set "rank" = rank_field_definition.rank where "id" = rank_field_definition.definition;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_field_definition"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_field_definition"(uuid, text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."field_definitions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_select on "better_supabase"."field_definitions" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_insert on "better_supabase"."field_definitions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_update on "better_supabase"."field_definitions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_delete on "better_supabase"."field_definitions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."field_values";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_values";
create policy bsb_tenant_scope_select on "better_supabase"."field_values" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_values";
create policy bsb_tenant_scope_insert on "better_supabase"."field_values" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_values";
create policy bsb_tenant_scope_update on "better_supabase"."field_values" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_values";
create policy bsb_tenant_scope_delete on "better_supabase"."field_values" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block-data custom-fields
-- @bsb-hash sha256:bf98d83435a0af9b755b2461111a0962ca26ead36da48b2f14a93ede844e6d0b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('custom-fields', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block custom-fields@3 managed
-- @bsb-hash sha256:75a06a88cf506eca42b8670bba13fb1ff71d0cba3ba0202259e6bb8f3f51b5ef
-- Field definitions, options and typed values. A sensitive value is readable only with the field's permission. Inline layout stores the definition on the value row.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_definitions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_values";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function "better_supabase"."bsb_valid_bsn"(value text)
returns boolean
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select case
    when value !~ '^[0-9]{9}$' or value = '000000000' then false
    else (
      select sum(substr(value, i, 1)::integer * case when i = 9 then -1 else 10 - i end)
      from generate_series(1, 9) as i
    ) % 11 = 0
  end
$$;
revoke execute on function "better_supabase"."bsb_valid_bsn"(text) from public, anon;
grant execute on function "better_supabase"."bsb_valid_bsn"(text) to authenticated, service_role;
create or replace function "better_supabase"."bsb_valid_iban"(value text)
returns boolean
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select case
    when value !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' then false
    else (
      select string_agg(case when ascii(c.ch) between 65 and 90 then (ascii(c.ch) - 55)::text else c.ch end, '' order by c.n)
      from regexp_split_to_table(substr(value, 5) || substr(value, 1, 4), '') with ordinality as c(ch, n)
    )::numeric % 97 = 1
  end
$$;
revoke execute on function "better_supabase"."bsb_valid_iban"(text) from public, anon;
grant execute on function "better_supabase"."bsb_valid_iban"(text) to authenticated, service_role;
-- A sensitive value is returned only when the caller holds the field's
-- permission, or custom_fields.sensitive.read when the field names none.
create table if not exists "better_supabase"."field_definitions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "entity" text not null,
  "key" text not null,
  "label" text not null,
  "type" text not null,
  "required" boolean not null default false,
  "sensitive" boolean not null default false,
  "permission" text,
  "encrypted" boolean not null default false,
  "rank" text collate "C" not null default 'V',
  unique ("tenant_id", "entity", "key")
);
alter table "better_supabase"."field_definitions" drop constraint if exists "field_definitions_type_check";
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."field_definitions"'::regclass and c.conname = 'bsb_field_definitions_type'
  ), 'pg_constraint'), '') <> 'better-supabase check 068e6990' then
    alter table "better_supabase"."field_definitions" drop constraint if exists "bsb_field_definitions_type";
    alter table "better_supabase"."field_definitions" add constraint "bsb_field_definitions_type" check ("type" in ('text', 'number', 'date', 'bool', 'option', 'json', 'email', 'url', 'multi_option', 'user', 'rating', 'currency', 'bsn', 'iban', 'phone_e164'));
    comment on constraint "bsb_field_definitions_type" on "better_supabase"."field_definitions" is 'better-supabase check 068e6990';
  end if;
end;
$$;
alter table "better_supabase"."field_definitions" enable row level security;
revoke all on "better_supabase"."field_definitions" from public, anon, authenticated;
grant select on "better_supabase"."field_definitions" to authenticated;
grant all on "better_supabase"."field_definitions" to service_role;
create table if not exists "better_supabase"."field_values" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "definition_id" uuid references "better_supabase"."field_definitions" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "value_text" text,
  "value_number" numeric,
  "value_date" date,
  "value_bool" boolean,
  "option_id" uuid,
  "value_json" jsonb
  , unique ("tenant_id", "subject_type", "subject_id", "definition_id")
);
alter table "better_supabase"."field_values" enable row level security;
revoke all on "better_supabase"."field_values" from public, anon, authenticated;
grant select on "better_supabase"."field_values" to authenticated;
grant all on "better_supabase"."field_values" to service_role;
create index if not exists field_values_definition_idx on "better_supabase"."field_values" ("definition_id");

create or replace function "better_supabase"."save_field_definition"(tenant uuid, entity text, key text, label text, type text, sensitive boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_field_definition.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  select max(d."rank" collate "C") into v_last from "better_supabase"."field_definitions" d
    where d."tenant_id" = save_field_definition.tenant and d."entity" = save_field_definition.entity;
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."field_definitions" ("tenant_id", "entity", "key", "label", "type", "sensitive", "rank")
  values (save_field_definition.tenant, save_field_definition.entity, save_field_definition.key, save_field_definition.label, save_field_definition.type, coalesce(save_field_definition.sensitive, false), v_rank)
  on conflict ("tenant_id", "entity", "key")
  do update set "label" = excluded."label", "sensitive" = excluded."sensitive"
  returning "id" into v_id;
  perform "better_supabase".emit_event('custom_field.saved', jsonb_build_object('organizationId', save_field_definition.tenant, 'id', v_id, 'entity', save_field_definition.entity), 'custom-fields/' || coalesce(v_id::text, save_field_definition.key), (save_field_definition.tenant)::text, null, 'better-supabase/custom-fields');
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) to authenticated, service_role;

create or replace function "better_supabase"."read_field_values"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_values jsonb;
  v_key text;
begin
  v_key := "better_supabase"."field_key"('tenant:' || read_field_values.tenant::text, false);
  select coalesce(jsonb_agg(jsonb_build_object('id', v."id", 'text', case when coalesce(d."encrypted", false) then "better_supabase"."field_open"(v_key, v."value_text") else v."value_text" end)), '[]'::jsonb)
  into v_values
  from "better_supabase"."field_values" v
  left join "better_supabase"."field_definitions" d on d."id" = v."definition_id"
  where v."tenant_id" = read_field_values.tenant
    and v."subject_type" = read_field_values.subject_type
    and v."subject_id" = read_field_values.subject_id
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', read_field_values.tenant, 'custom_fields.read'), false))
    and (not coalesce(d."sensitive", false)
        or coalesce(better_supabase.can('tenant', v."tenant_id", coalesce(d."permission", 'custom_fields.read_sensitive')), false));
  return v_values;
end;
$$;
revoke execute on function "better_supabase"."read_field_values"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."read_field_values"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."set_field_value"(tenant uuid, subject_type text, subject_id text, definition uuid, value text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_field_value.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to set custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and not (case d."type" when 'bsn' then "better_supabase"."bsb_valid_bsn"(set_field_value.value) when 'iban' then "better_supabase"."bsb_valid_iban"(set_field_value.value) when 'phone_e164' then set_field_value.value ~* '^\+[1-9][0-9]{1,14}$' else true end)) then
    raise exception 'the value doesn''t match the field''s format' using errcode = '22023', hint = 'FIELD_VALUE_INVALID';
  end if;
  insert into "better_supabase"."field_values" ("tenant_id", "definition_id", "subject_type", "subject_id", "value_text")
  values (set_field_value.tenant, set_field_value.definition, set_field_value.subject_type, set_field_value.subject_id, case when exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and d."encrypted") then "better_supabase"."field_encrypt"('tenant:' || set_field_value.tenant::text, set_field_value.value) else set_field_value.value end)
  returning "id" into v_id;
  perform "better_supabase".emit_event('field_value.set', jsonb_build_object('organizationId', set_field_value.tenant, 'id', v_id, 'subjectType', set_field_value.subject_type, 'subjectId', set_field_value.subject_id), 'field-values/' || v_id::text, (set_field_value.tenant)::text, null, 'better-supabase/custom-fields');
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."set_field_value"(uuid, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."set_field_value"(uuid, text, text, uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_field_definition"(definition uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."field_definitions" where "id" = delete_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  delete from "better_supabase"."field_definitions" where "id" = delete_field_definition.definition;
  perform "better_supabase".emit_event('custom_field.deleted', jsonb_build_object('organizationId', v_tenant, 'id', delete_field_definition.definition), 'custom-fields/' || delete_field_definition.definition::text, (v_tenant)::text, null, 'better-supabase/custom-fields');
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_field_definition"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_field_definition"(uuid) to authenticated, service_role;

-- The definitions of one entity in display order.
create or replace function "better_supabase"."list_field_definitions"(tenant uuid, entity text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'rank', d."rank"
  ) order by d."rank" collate "C", d."key"), '[]'::jsonb)
  from "better_supabase"."field_definitions" d
  where d."tenant_id" = list_field_definitions.tenant
    and d."entity" = list_field_definitions.entity
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_field_definitions.tenant, 'custom_fields.read'), false))
$$;
revoke execute on function "better_supabase"."list_field_definitions"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_field_definitions"(uuid, text) to authenticated, service_role;

-- Sets a field's rank key, from rankBetween over its neighbours' keys.
create or replace function "better_supabase"."rank_field_definition"(definition uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_field_definition.rank is null or rank_field_definition.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'FIELD_RANK_INVALID';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."field_definitions" where "id" = rank_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  update "better_supabase"."field_definitions" set "rank" = rank_field_definition.rank where "id" = rank_field_definition.definition;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_field_definition"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_field_definition"(uuid, text) to authenticated, service_role;

-- Encrypts a text field and the values it already has. It can't be undone.
create or replace function "better_supabase"."encrypt_field_definition"(definition uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_type text;
  v_key text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "type" into v_tenant, v_type from "better_supabase"."field_definitions" where "id" = encrypt_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if v_type not in ('text', 'email', 'url', 'bsn', 'iban', 'phone_e164') then
    raise exception 'only text fields can be encrypted' using errcode = '22023', hint = 'FIELD_NOT_ENCRYPTABLE';
  end if;
  v_key := "better_supabase"."field_key"('tenant:' || v_tenant::text, true);
  update "better_supabase"."field_definitions" set "encrypted" = true where "id" = encrypt_field_definition.definition;
  update "better_supabase"."field_values" set "value_text" = "better_supabase"."field_seal"(v_key, "value_text")
  where "definition_id" = encrypt_field_definition.definition
    and "value_text" is not null
    and left("value_text", 5) <> 'bsf1:';
  return true;
end;
$$;
revoke execute on function "better_supabase"."encrypt_field_definition"(uuid) from public, anon;
grant execute on function "better_supabase"."encrypt_field_definition"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."field_definitions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_select on "better_supabase"."field_definitions" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_insert on "better_supabase"."field_definitions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_update on "better_supabase"."field_definitions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_delete on "better_supabase"."field_definitions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."field_values";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_values";
create policy bsb_tenant_scope_select on "better_supabase"."field_values" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_values";
create policy bsb_tenant_scope_insert on "better_supabase"."field_values" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_values";
create policy bsb_tenant_scope_update on "better_supabase"."field_values" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_values";
create policy bsb_tenant_scope_delete on "better_supabase"."field_values" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block-data custom-fields
-- @bsb-hash sha256:bf98d83435a0af9b755b2461111a0962ca26ead36da48b2f14a93ede844e6d0b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('custom-fields', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block custom-fields@3 managed
-- @bsb-hash sha256:ac05fe7fea926c685e51b9b524e572c29b7b1584855ceab48cb44c943c10cb2c
-- Field definitions, options and typed values. A sensitive value is readable only with the field's permission. Inline layout stores the definition on the value row.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
    drop policy if exists bsb_tenant_scope on "app_private"."field_definitions";
    drop policy if exists bsb_tenant_scope_select on "app_private"."field_definitions";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."field_definitions";
    drop policy if exists bsb_tenant_scope_update on "app_private"."field_definitions";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."field_definitions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."field_values";
    drop policy if exists bsb_tenant_scope_select on "app_private"."field_values";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."field_values";
    drop policy if exists bsb_tenant_scope_update on "app_private"."field_values";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."field_values";
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
create or replace function "app_private"."bsb_valid_bsn"(value text)
returns boolean
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select case
    when value !~ '^[0-9]{9}$' or value = '000000000' then false
    else (
      select sum(substr(value, i, 1)::integer * case when i = 9 then -1 else 10 - i end)
      from generate_series(1, 9) as i
    ) % 11 = 0
  end
$$;
revoke execute on function "app_private"."bsb_valid_bsn"(text) from public, anon;
grant execute on function "app_private"."bsb_valid_bsn"(text) to authenticated, service_role;
create or replace function "app_private"."bsb_valid_iban"(value text)
returns boolean
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select case
    when value !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' then false
    else (
      select string_agg(case when ascii(c.ch) between 65 and 90 then (ascii(c.ch) - 55)::text else c.ch end, '' order by c.n)
      from regexp_split_to_table(substr(value, 5) || substr(value, 1, 4), '') with ordinality as c(ch, n)
    )::numeric % 97 = 1
  end
$$;
revoke execute on function "app_private"."bsb_valid_iban"(text) from public, anon;
grant execute on function "app_private"."bsb_valid_iban"(text) to authenticated, service_role;
-- A sensitive value is returned only when the caller holds the field's
-- permission, or custom_fields.sensitive.read when the field names none.
create table if not exists "app_private"."field_definitions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "entity" text not null,
  "key" text not null,
  "label" text not null,
  "type" text not null,
  "required" boolean not null default false,
  "sensitive" boolean not null default false,
  "permission" text,
  "encrypted" boolean not null default false,
  "rank" text collate "C" not null default 'V',
  unique ("tenant_id", "entity", "key")
);
alter table "app_private"."field_definitions" drop constraint if exists "field_definitions_type_check";
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"app_private"."field_definitions"'::regclass and c.conname = 'bsb_field_definitions_type'
  ), 'pg_constraint'), '') <> 'better-supabase check 068e6990' then
    alter table "app_private"."field_definitions" drop constraint if exists "bsb_field_definitions_type";
    alter table "app_private"."field_definitions" add constraint "bsb_field_definitions_type" check ("type" in ('text', 'number', 'date', 'bool', 'option', 'json', 'email', 'url', 'multi_option', 'user', 'rating', 'currency', 'bsn', 'iban', 'phone_e164'));
    comment on constraint "bsb_field_definitions_type" on "app_private"."field_definitions" is 'better-supabase check 068e6990';
  end if;
end;
$$;
alter table "app_private"."field_definitions" enable row level security;
revoke all on "app_private"."field_definitions" from public, anon, authenticated;
grant select on "app_private"."field_definitions" to authenticated;
grant all on "app_private"."field_definitions" to service_role;
create table if not exists "app_private"."field_values" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "definition_id" uuid references "app_private"."field_definitions" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "value_text" text,
  "value_number" numeric,
  "value_date" date,
  "value_bool" boolean,
  "option_id" uuid,
  "value_json" jsonb
  , unique ("tenant_id", "subject_type", "subject_id", "definition_id")
);
alter table "app_private"."field_values" enable row level security;
revoke all on "app_private"."field_values" from public, anon, authenticated;
grant select on "app_private"."field_values" to authenticated;
grant all on "app_private"."field_values" to service_role;
create index if not exists field_values_definition_idx on "app_private"."field_values" ("definition_id");

create or replace function "app_private"."save_field_definition"(tenant uuid, entity text, key text, label text, type text, sensitive boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_field_definition.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  select max(d."rank" collate "C") into v_last from "app_private"."field_definitions" d
    where d."tenant_id" = save_field_definition.tenant and d."entity" = save_field_definition.entity;
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "app_private"."field_definitions" ("tenant_id", "entity", "key", "label", "type", "sensitive", "rank")
  values (save_field_definition.tenant, save_field_definition.entity, save_field_definition.key, save_field_definition.label, save_field_definition.type, coalesce(save_field_definition.sensitive, false), v_rank)
  on conflict ("tenant_id", "entity", "key")
  do update set "label" = excluded."label", "sensitive" = excluded."sensitive"
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "app_private"."save_field_definition"(uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "app_private"."save_field_definition"(uuid, text, text, text, text, boolean) to authenticated, service_role;

create or replace function "app_private"."read_field_values"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_values jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id', v."id", 'text', v."value_text")), '[]'::jsonb)
  into v_values
  from "app_private"."field_values" v
  left join "app_private"."field_definitions" d on d."id" = v."definition_id"
  where v."tenant_id" = read_field_values.tenant
    and v."subject_type" = read_field_values.subject_type
    and v."subject_id" = read_field_values.subject_id
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', read_field_values.tenant, 'custom_fields.read'), false))
    and (not coalesce(d."sensitive", false)
        or coalesce(better_supabase.can('tenant', v."tenant_id", coalesce(d."permission", 'custom_fields.read_sensitive')), false));
  return v_values;
end;
$$;
revoke execute on function "app_private"."read_field_values"(uuid, text, text) from public, anon;
grant execute on function "app_private"."read_field_values"(uuid, text, text) to authenticated, service_role;

create or replace function "app_private"."set_field_value"(tenant uuid, subject_type text, subject_id text, definition uuid, value text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_field_value.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to set custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if exists (select 1 from "app_private"."field_definitions" d where d."id" = set_field_value.definition and not (case d."type" when 'bsn' then "app_private"."bsb_valid_bsn"(set_field_value.value) when 'iban' then "app_private"."bsb_valid_iban"(set_field_value.value) when 'phone_e164' then set_field_value.value ~* '^\+[1-9][0-9]{1,14}$' else true end)) then
    raise exception 'the value doesn''t match the field''s format' using errcode = '22023', hint = 'FIELD_VALUE_INVALID';
  end if;
  insert into "app_private"."field_values" ("tenant_id", "definition_id", "subject_type", "subject_id", "value_text")
  values (set_field_value.tenant, set_field_value.definition, set_field_value.subject_type, set_field_value.subject_id, set_field_value.value)
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "app_private"."set_field_value"(uuid, text, text, uuid, text) from public, anon;
grant execute on function "app_private"."set_field_value"(uuid, text, text, uuid, text) to authenticated, service_role;

create or replace function "app_private"."delete_field_definition"(definition uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "app_private"."field_definitions" where "id" = delete_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  delete from "app_private"."field_definitions" where "id" = delete_field_definition.definition;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_field_definition"(uuid) from public, anon;
grant execute on function "app_private"."delete_field_definition"(uuid) to authenticated, service_role;

-- The definitions of one entity in display order.
create or replace function "app_private"."list_field_definitions"(tenant uuid, entity text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'rank', d."rank"
  ) order by d."rank" collate "C", d."key"), '[]'::jsonb)
  from "app_private"."field_definitions" d
  where d."tenant_id" = list_field_definitions.tenant
    and d."entity" = list_field_definitions.entity
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_field_definitions.tenant, 'custom_fields.read'), false))
$$;
revoke execute on function "app_private"."list_field_definitions"(uuid, text) from public, anon;
grant execute on function "app_private"."list_field_definitions"(uuid, text) to authenticated, service_role;

-- Sets a field's rank key, from rankBetween over its neighbours' keys.
create or replace function "app_private"."rank_field_definition"(definition uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_field_definition.rank is null or rank_field_definition.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'FIELD_RANK_INVALID';
  end if;
  select "tenant_id" into v_tenant from "app_private"."field_definitions" where "id" = rank_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  update "app_private"."field_definitions" set "rank" = rank_field_definition.rank where "id" = rank_field_definition.definition;
  return true;
end;
$$;
revoke execute on function "app_private"."rank_field_definition"(uuid, text) from public, anon;
grant execute on function "app_private"."rank_field_definition"(uuid, text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "app_private"."field_definitions";
drop policy if exists bsb_tenant_scope_select on "app_private"."field_definitions";
create policy bsb_tenant_scope_select on "app_private"."field_definitions" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "app_private"."field_definitions";
create policy bsb_tenant_scope_insert on "app_private"."field_definitions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."field_definitions";
create policy bsb_tenant_scope_update on "app_private"."field_definitions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."field_definitions";
create policy bsb_tenant_scope_delete on "app_private"."field_definitions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."field_values";
drop policy if exists bsb_tenant_scope_select on "app_private"."field_values";
create policy bsb_tenant_scope_select on "app_private"."field_values" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "app_private"."field_values";
create policy bsb_tenant_scope_insert on "app_private"."field_values" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."field_values";
create policy bsb_tenant_scope_update on "app_private"."field_values" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."field_values";
create policy bsb_tenant_scope_delete on "app_private"."field_values" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block-data custom-fields
-- @bsb-hash sha256:bf98d83435a0af9b755b2461111a0962ca26ead36da48b2f14a93ede844e6d0b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('custom-fields', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block custom-fields@3 managed
-- @bsb-hash sha256:70bad148c2a137532a9fad91e62081d74ca8fc4cf1e90249062d136cf8935b7f
-- Field definitions, options and typed values. A sensitive value is readable only with the field's permission. Inline layout stores the definition on the value row.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_definitions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_values";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function "better_supabase"."bsb_valid_bsn"(value text)
returns boolean
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select case
    when value !~ '^[0-9]{9}$' or value = '000000000' then false
    else (
      select sum(substr(value, i, 1)::integer * case when i = 9 then -1 else 10 - i end)
      from generate_series(1, 9) as i
    ) % 11 = 0
  end
$$;
revoke execute on function "better_supabase"."bsb_valid_bsn"(text) from public, anon;
grant execute on function "better_supabase"."bsb_valid_bsn"(text) to authenticated, service_role;
create or replace function "better_supabase"."bsb_valid_iban"(value text)
returns boolean
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select case
    when value !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' then false
    else (
      select string_agg(case when ascii(c.ch) between 65 and 90 then (ascii(c.ch) - 55)::text else c.ch end, '' order by c.n)
      from regexp_split_to_table(substr(value, 5) || substr(value, 1, 4), '') with ordinality as c(ch, n)
    )::numeric % 97 = 1
  end
$$;
revoke execute on function "better_supabase"."bsb_valid_iban"(text) from public, anon;
grant execute on function "better_supabase"."bsb_valid_iban"(text) to authenticated, service_role;
-- A sensitive value is returned only when the caller holds the field's
-- permission, or custom_fields.sensitive.read when the field names none.
create table if not exists "better_supabase"."field_definitions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "entity" text not null,
  "key" text not null,
  "label" text not null,
  "type" text not null,
  "required" boolean not null default false,
  "sensitive" boolean not null default false,
  "permission" text,
  "encrypted" boolean not null default false,
  "rank" text collate "C" not null default 'V',
  unique ("tenant_id", "entity", "key")
);
alter table "better_supabase"."field_definitions" drop constraint if exists "field_definitions_type_check";
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."field_definitions"'::regclass and c.conname = 'bsb_field_definitions_type'
  ), 'pg_constraint'), '') <> 'better-supabase check 068e6990' then
    alter table "better_supabase"."field_definitions" drop constraint if exists "bsb_field_definitions_type";
    alter table "better_supabase"."field_definitions" add constraint "bsb_field_definitions_type" check ("type" in ('text', 'number', 'date', 'bool', 'option', 'json', 'email', 'url', 'multi_option', 'user', 'rating', 'currency', 'bsn', 'iban', 'phone_e164'));
    comment on constraint "bsb_field_definitions_type" on "better_supabase"."field_definitions" is 'better-supabase check 068e6990';
  end if;
end;
$$;
alter table "better_supabase"."field_definitions" enable row level security;
revoke all on "better_supabase"."field_definitions" from public, anon, authenticated;
grant select on "better_supabase"."field_definitions" to authenticated;
grant all on "better_supabase"."field_definitions" to service_role;
create table if not exists "better_supabase"."field_values" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "definition_id" uuid references "better_supabase"."field_definitions" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "value_text" text,
  "value_number" numeric,
  "value_date" date,
  "value_bool" boolean,
  "option_id" uuid,
  "value_json" jsonb
  , unique ("tenant_id", "subject_type", "subject_id", "definition_id")
);
alter table "better_supabase"."field_values" enable row level security;
revoke all on "better_supabase"."field_values" from public, anon, authenticated;
grant select on "better_supabase"."field_values" to authenticated;
grant all on "better_supabase"."field_values" to service_role;
create index if not exists field_values_definition_idx on "better_supabase"."field_values" ("definition_id");

create or replace function "better_supabase"."save_field_definition"(tenant uuid, entity text, key text, label text, type text, sensitive boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_field_definition.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  select max(d."rank" collate "C") into v_last from "better_supabase"."field_definitions" d
    where d."tenant_id" = save_field_definition.tenant and d."entity" = save_field_definition.entity;
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."field_definitions" ("tenant_id", "entity", "key", "label", "type", "sensitive", "rank")
  values (save_field_definition.tenant, save_field_definition.entity, save_field_definition.key, save_field_definition.label, save_field_definition.type, coalesce(save_field_definition.sensitive, false), v_rank)
  on conflict ("tenant_id", "entity", "key")
  do update set "label" = excluded."label", "sensitive" = excluded."sensitive"
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) to authenticated, service_role;

create or replace function "better_supabase"."read_field_values"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_values jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id', v."id", 'text', v."value_text")), '[]'::jsonb)
  into v_values
  from "better_supabase"."field_values" v
  left join "better_supabase"."field_definitions" d on d."id" = v."definition_id"
  where v."tenant_id" = read_field_values.tenant
    and v."subject_type" = read_field_values.subject_type
    and v."subject_id" = read_field_values.subject_id
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', read_field_values.tenant, 'custom_fields.read'), false))
    and (not coalesce(d."sensitive", false)
        or coalesce(better_supabase.can('tenant', v."tenant_id", coalesce(d."permission", 'custom_fields.read_sensitive')), false));
  return v_values;
end;
$$;
revoke execute on function "better_supabase"."read_field_values"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."read_field_values"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."set_field_value"(tenant uuid, subject_type text, subject_id text, definition uuid, value text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_field_value.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to set custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and not (case d."type" when 'bsn' then "better_supabase"."bsb_valid_bsn"(set_field_value.value) when 'iban' then "better_supabase"."bsb_valid_iban"(set_field_value.value) when 'phone_e164' then set_field_value.value ~* '^\+[1-9][0-9]{1,14}$' else true end)) then
    raise exception 'the value doesn''t match the field''s format' using errcode = '22023', hint = 'FIELD_VALUE_INVALID';
  end if;
  insert into "better_supabase"."field_values" ("tenant_id", "definition_id", "subject_type", "subject_id", "value_text")
  values (set_field_value.tenant, set_field_value.definition, set_field_value.subject_type, set_field_value.subject_id, set_field_value.value)
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."set_field_value"(uuid, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."set_field_value"(uuid, text, text, uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_field_definition"(definition uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."field_definitions" where "id" = delete_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  delete from "better_supabase"."field_definitions" where "id" = delete_field_definition.definition;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_field_definition"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_field_definition"(uuid) to authenticated, service_role;

-- The definitions of one entity in display order.
create or replace function "better_supabase"."list_field_definitions"(tenant uuid, entity text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'rank', d."rank"
  ) order by d."rank" collate "C", d."key"), '[]'::jsonb)
  from "better_supabase"."field_definitions" d
  where d."tenant_id" = list_field_definitions.tenant
    and d."entity" = list_field_definitions.entity
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_field_definitions.tenant, 'custom_fields.read'), false))
$$;
revoke execute on function "better_supabase"."list_field_definitions"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_field_definitions"(uuid, text) to authenticated, service_role;

-- Sets a field's rank key, from rankBetween over its neighbours' keys.
create or replace function "better_supabase"."rank_field_definition"(definition uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_field_definition.rank is null or rank_field_definition.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'FIELD_RANK_INVALID';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."field_definitions" where "id" = rank_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  update "better_supabase"."field_definitions" set "rank" = rank_field_definition.rank where "id" = rank_field_definition.definition;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_field_definition"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_field_definition"(uuid, text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."field_definitions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_select on "better_supabase"."field_definitions" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_insert on "better_supabase"."field_definitions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_update on "better_supabase"."field_definitions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_delete on "better_supabase"."field_definitions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."field_values";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_values";
create policy bsb_tenant_scope_select on "better_supabase"."field_values" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_values";
create policy bsb_tenant_scope_insert on "better_supabase"."field_values" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_values";
create policy bsb_tenant_scope_update on "better_supabase"."field_values" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_values";
create policy bsb_tenant_scope_delete on "better_supabase"."field_values" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.custom-fields.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

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

create or replace function "api"."bsb_valid_bsn"(value text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."bsb_valid_bsn"($1) $$;
revoke execute on function "api"."bsb_valid_bsn"(text) from public, anon;
grant execute on function "api"."bsb_valid_bsn"(text) to authenticated, service_role;

create or replace function "api"."bsb_valid_iban"(value text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."bsb_valid_iban"($1) $$;
revoke execute on function "api"."bsb_valid_iban"(text) from public, anon;
grant execute on function "api"."bsb_valid_iban"(text) to authenticated, service_role;

create or replace function "api"."save_field_definition"(tenant uuid, entity text, key text, label text, type text, sensitive boolean)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_field_definition"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."save_field_definition"(uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "api"."save_field_definition"(uuid, text, text, text, text, boolean) to authenticated, service_role;

create or replace function "api"."read_field_values"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."read_field_values"($1, $2, $3) $$;
revoke execute on function "api"."read_field_values"(uuid, text, text) from public, anon;
grant execute on function "api"."read_field_values"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."set_field_value"(tenant uuid, subject_type text, subject_id text, definition uuid, value text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_field_value"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."set_field_value"(uuid, text, text, uuid, text) from public, anon;
grant execute on function "api"."set_field_value"(uuid, text, text, uuid, text) to authenticated, service_role;

create or replace function "api"."delete_field_definition"(definition uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_field_definition"($1) $$;
revoke execute on function "api"."delete_field_definition"(uuid) from public, anon;
grant execute on function "api"."delete_field_definition"(uuid) to authenticated, service_role;

create or replace function "api"."list_field_definitions"(tenant uuid, entity text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_field_definitions"($1, $2) $$;
revoke execute on function "api"."list_field_definitions"(uuid, text) from public, anon;
grant execute on function "api"."list_field_definitions"(uuid, text) to authenticated, service_role;

create or replace function "api"."rank_field_definition"(definition uuid, rank text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rank_field_definition"($1, $2) $$;
revoke execute on function "api"."rank_field_definition"(uuid, text) from public, anon;
grant execute on function "api"."rank_field_definition"(uuid, text) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block-data custom-fields
-- @bsb-hash sha256:bf98d83435a0af9b755b2461111a0962ca26ead36da48b2f14a93ede844e6d0b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('custom-fields', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block custom-fields@3 managed
-- @bsb-hash sha256:82a637e7ff83f9b06763ea4069ec99e161a2245c5de005bfdeac6bea524346c3
-- Field definitions, options and typed values. A sensitive value is readable only with the field's permission. Inline layout stores the definition on the value row.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_definitions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_values";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function "better_supabase"."bsb_valid_bsn"(value text)
returns boolean
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select case
    when value !~ '^[0-9]{9}$' or value = '000000000' then false
    else (
      select sum(substr(value, i, 1)::integer * case when i = 9 then -1 else 10 - i end)
      from generate_series(1, 9) as i
    ) % 11 = 0
  end
$$;
revoke execute on function "better_supabase"."bsb_valid_bsn"(text) from public, anon;
grant execute on function "better_supabase"."bsb_valid_bsn"(text) to authenticated, service_role;
create or replace function "better_supabase"."bsb_valid_iban"(value text)
returns boolean
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select case
    when value !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' then false
    else (
      select string_agg(case when ascii(c.ch) between 65 and 90 then (ascii(c.ch) - 55)::text else c.ch end, '' order by c.n)
      from regexp_split_to_table(substr(value, 5) || substr(value, 1, 4), '') with ordinality as c(ch, n)
    )::numeric % 97 = 1
  end
$$;
revoke execute on function "better_supabase"."bsb_valid_iban"(text) from public, anon;
grant execute on function "better_supabase"."bsb_valid_iban"(text) to authenticated, service_role;
-- A sensitive value is returned only when the caller holds the field's
-- permission, or custom_fields.sensitive.read when the field names none.
-- better_supabase.field_definitions is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."field_definitions" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."field_definitions" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."field_definitions" add column if not exists "entity" text;
alter table "better_supabase"."field_definitions" add column if not exists "key" text;
alter table "better_supabase"."field_definitions" add column if not exists "label" text;
alter table "better_supabase"."field_definitions" add column if not exists "type" text;
alter table "better_supabase"."field_definitions" add column if not exists "required" boolean not null default false;
alter table "better_supabase"."field_definitions" add column if not exists "sensitive" boolean not null default false;
alter table "better_supabase"."field_definitions" add column if not exists "permission" text;
alter table "better_supabase"."field_definitions" add column if not exists "encrypted" boolean not null default false;
alter table "better_supabase"."field_definitions" add column if not exists "rank" text collate "C" not null default 'V';
alter table "better_supabase"."field_definitions" enable row level security;
grant select on "better_supabase"."field_definitions" to authenticated;
grant all on "better_supabase"."field_definitions" to service_role;
-- better_supabase.field_values is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."field_values" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."field_values" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."field_values" add column if not exists "definition_id" uuid references "better_supabase"."field_definitions" ("id") on delete cascade;
alter table "better_supabase"."field_values" add column if not exists "subject_type" text;
alter table "better_supabase"."field_values" add column if not exists "subject_id" text;
alter table "better_supabase"."field_values" add column if not exists "value_text" text;
alter table "better_supabase"."field_values" add column if not exists "value_number" numeric;
alter table "better_supabase"."field_values" add column if not exists "value_date" date;
alter table "better_supabase"."field_values" add column if not exists "value_bool" boolean;
alter table "better_supabase"."field_values" add column if not exists "option_id" uuid;
alter table "better_supabase"."field_values" add column if not exists "value_json" jsonb;
alter table "better_supabase"."field_values" enable row level security;
grant select on "better_supabase"."field_values" to authenticated;
grant all on "better_supabase"."field_values" to service_role;
create index if not exists field_values_definition_idx on "better_supabase"."field_values" ("definition_id");

create or replace function "better_supabase"."save_field_definition"(tenant uuid, entity text, key text, label text, type text, sensitive boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_field_definition.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  select max(d."rank" collate "C") into v_last from "better_supabase"."field_definitions" d
    where d."tenant_id" = save_field_definition.tenant and d."entity" = save_field_definition.entity;
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."field_definitions" ("tenant_id", "entity", "key", "label", "type", "sensitive", "rank")
  values (save_field_definition.tenant, save_field_definition.entity, save_field_definition.key, save_field_definition.label, save_field_definition.type, coalesce(save_field_definition.sensitive, false), v_rank)
  on conflict ("tenant_id", "entity", "key")
  do update set "label" = excluded."label", "sensitive" = excluded."sensitive"
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) to authenticated, service_role;

create or replace function "better_supabase"."read_field_values"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_values jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id', v."id", 'text', v."value_text")), '[]'::jsonb)
  into v_values
  from "better_supabase"."field_values" v
  left join "better_supabase"."field_definitions" d on d."id" = v."definition_id"
  where v."tenant_id" = read_field_values.tenant
    and v."subject_type" = read_field_values.subject_type
    and v."subject_id" = read_field_values.subject_id
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', read_field_values.tenant, 'custom_fields.read'), false))
    and (not coalesce(d."sensitive", false)
        or coalesce(better_supabase.can('tenant', v."tenant_id", coalesce(d."permission", 'custom_fields.read_sensitive')), false));
  return v_values;
end;
$$;
revoke execute on function "better_supabase"."read_field_values"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."read_field_values"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."set_field_value"(tenant uuid, subject_type text, subject_id text, definition uuid, value text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_field_value.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to set custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and not (case d."type" when 'bsn' then "better_supabase"."bsb_valid_bsn"(set_field_value.value) when 'iban' then "better_supabase"."bsb_valid_iban"(set_field_value.value) when 'phone_e164' then set_field_value.value ~* '^\+[1-9][0-9]{1,14}$' else true end)) then
    raise exception 'the value doesn''t match the field''s format' using errcode = '22023', hint = 'FIELD_VALUE_INVALID';
  end if;
  insert into "better_supabase"."field_values" ("tenant_id", "definition_id", "subject_type", "subject_id", "value_text")
  values (set_field_value.tenant, set_field_value.definition, set_field_value.subject_type, set_field_value.subject_id, set_field_value.value)
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."set_field_value"(uuid, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."set_field_value"(uuid, text, text, uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_field_definition"(definition uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."field_definitions" where "id" = delete_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  delete from "better_supabase"."field_definitions" where "id" = delete_field_definition.definition;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_field_definition"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_field_definition"(uuid) to authenticated, service_role;

-- The definitions of one entity in display order.
create or replace function "better_supabase"."list_field_definitions"(tenant uuid, entity text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'rank', d."rank"
  ) order by d."rank" collate "C", d."key"), '[]'::jsonb)
  from "better_supabase"."field_definitions" d
  where d."tenant_id" = list_field_definitions.tenant
    and d."entity" = list_field_definitions.entity
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_field_definitions.tenant, 'custom_fields.read'), false))
$$;
revoke execute on function "better_supabase"."list_field_definitions"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_field_definitions"(uuid, text) to authenticated, service_role;

-- Sets a field's rank key, from rankBetween over its neighbours' keys.
create or replace function "better_supabase"."rank_field_definition"(definition uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_field_definition.rank is null or rank_field_definition.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'FIELD_RANK_INVALID';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."field_definitions" where "id" = rank_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  update "better_supabase"."field_definitions" set "rank" = rank_field_definition.rank where "id" = rank_field_definition.definition;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_field_definition"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_field_definition"(uuid, text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."field_definitions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_select on "better_supabase"."field_definitions" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_insert on "better_supabase"."field_definitions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_update on "better_supabase"."field_definitions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_delete on "better_supabase"."field_definitions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."field_values";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_values";
create policy bsb_tenant_scope_select on "better_supabase"."field_values" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_values";
create policy bsb_tenant_scope_insert on "better_supabase"."field_values" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_values";
create policy bsb_tenant_scope_update on "better_supabase"."field_values" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_values";
create policy bsb_tenant_scope_delete on "better_supabase"."field_values" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block-data custom-fields
-- @bsb-hash sha256:bf98d83435a0af9b755b2461111a0962ca26ead36da48b2f14a93ede844e6d0b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('custom-fields', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block custom-fields@3 managed
-- @bsb-hash sha256:d6b674d39bc56c246e4b3d61f5eb44ef1188fd85c9417699a0d03b7a65498ce3
-- Field definitions, options and typed values. A sensitive value is readable only with the field's permission. Inline layout stores the definition on the value row.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_definitions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_definitions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_values";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_values";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function "better_supabase"."bsb_valid_bsn"(value text)
returns boolean
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select case
    when value !~ '^[0-9]{9}$' or value = '000000000' then false
    else (
      select sum(substr(value, i, 1)::integer * case when i = 9 then -1 else 10 - i end)
      from generate_series(1, 9) as i
    ) % 11 = 0
  end
$$;
revoke execute on function "better_supabase"."bsb_valid_bsn"(text) from public, anon;
grant execute on function "better_supabase"."bsb_valid_bsn"(text) to authenticated, service_role;
create or replace function "better_supabase"."bsb_valid_iban"(value text)
returns boolean
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select case
    when value !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' then false
    else (
      select string_agg(case when ascii(c.ch) between 65 and 90 then (ascii(c.ch) - 55)::text else c.ch end, '' order by c.n)
      from regexp_split_to_table(substr(value, 5) || substr(value, 1, 4), '') with ordinality as c(ch, n)
    )::numeric % 97 = 1
  end
$$;
revoke execute on function "better_supabase"."bsb_valid_iban"(text) from public, anon;
grant execute on function "better_supabase"."bsb_valid_iban"(text) to authenticated, service_role;
-- A sensitive value is returned only when the caller holds the field's
-- permission, or custom_fields.sensitive.read when the field names none.
create table if not exists "better_supabase"."field_definitions" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "entity" text not null,
  "key" text not null,
  "label" text not null,
  "type" text not null,
  "required" boolean not null default false,
  "sensitive" boolean not null default false,
  "permission" text,
  "encrypted" boolean not null default false,
  "rank" text collate "C" not null default 'V',
  unique ("org_id", "entity", "key")
);
alter table "better_supabase"."field_definitions" drop constraint if exists "field_definitions_type_check";
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."field_definitions"'::regclass and c.conname = 'bsb_field_definitions_type'
  ), 'pg_constraint'), '') <> 'better-supabase check 068e6990' then
    alter table "better_supabase"."field_definitions" drop constraint if exists "bsb_field_definitions_type";
    alter table "better_supabase"."field_definitions" add constraint "bsb_field_definitions_type" check ("type" in ('text', 'number', 'date', 'bool', 'option', 'json', 'email', 'url', 'multi_option', 'user', 'rating', 'currency', 'bsn', 'iban', 'phone_e164'));
    comment on constraint "bsb_field_definitions_type" on "better_supabase"."field_definitions" is 'better-supabase check 068e6990';
  end if;
end;
$$;
alter table "better_supabase"."field_definitions" enable row level security;
revoke all on "better_supabase"."field_definitions" from public, anon, authenticated;
grant select on "better_supabase"."field_definitions" to authenticated;
grant all on "better_supabase"."field_definitions" to service_role;
create table if not exists "better_supabase"."field_values" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "definition_id" uuid references "better_supabase"."field_definitions" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "value_text" text,
  "value_number" numeric,
  "value_date" date,
  "value_bool" boolean,
  "option_id" uuid,
  "value_json" jsonb
  , unique ("org_id", "subject_type", "subject_id", "definition_id")
);
alter table "better_supabase"."field_values" enable row level security;
revoke all on "better_supabase"."field_values" from public, anon, authenticated;
grant select on "better_supabase"."field_values" to authenticated;
grant all on "better_supabase"."field_values" to service_role;
create index if not exists field_values_definition_idx on "better_supabase"."field_values" ("definition_id");

create or replace function "better_supabase"."save_field_definition"(tenant uuid, entity text, key text, label text, type text, sensitive boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_field_definition.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  select max(d."rank" collate "C") into v_last from "better_supabase"."field_definitions" d
    where d."org_id" = save_field_definition.tenant and d."entity" = save_field_definition.entity;
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."field_definitions" ("org_id", "entity", "key", "label", "type", "sensitive", "rank")
  values (save_field_definition.tenant, save_field_definition.entity, save_field_definition.key, save_field_definition.label, save_field_definition.type, coalesce(save_field_definition.sensitive, false), v_rank)
  on conflict ("org_id", "entity", "key")
  do update set "label" = excluded."label", "sensitive" = excluded."sensitive"
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) to authenticated, service_role;

create or replace function "better_supabase"."read_field_values"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_values jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id', v."id", 'text', v."value_text")), '[]'::jsonb)
  into v_values
  from "better_supabase"."field_values" v
  left join "better_supabase"."field_definitions" d on d."id" = v."definition_id"
  where v."org_id" = read_field_values.tenant
    and v."subject_type" = read_field_values.subject_type
    and v."subject_id" = read_field_values.subject_id
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', read_field_values.tenant, 'custom_fields.read'), false))
    and (not coalesce(d."sensitive", false)
        or coalesce(better_supabase.can('tenant', v."org_id", coalesce(d."permission", 'custom_fields.read_sensitive')), false));
  return v_values;
end;
$$;
revoke execute on function "better_supabase"."read_field_values"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."read_field_values"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."set_field_value"(tenant uuid, subject_type text, subject_id text, definition uuid, value text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_field_value.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to set custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and not (case d."type" when 'bsn' then "better_supabase"."bsb_valid_bsn"(set_field_value.value) when 'iban' then "better_supabase"."bsb_valid_iban"(set_field_value.value) when 'phone_e164' then set_field_value.value ~* '^\+[1-9][0-9]{1,14}$' else true end)) then
    raise exception 'the value doesn''t match the field''s format' using errcode = '22023', hint = 'FIELD_VALUE_INVALID';
  end if;
  insert into "better_supabase"."field_values" ("org_id", "definition_id", "subject_type", "subject_id", "value_text")
  values (set_field_value.tenant, set_field_value.definition, set_field_value.subject_type, set_field_value.subject_id, set_field_value.value)
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."set_field_value"(uuid, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."set_field_value"(uuid, text, text, uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_field_definition"(definition uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "org_id" into v_tenant from "better_supabase"."field_definitions" where "id" = delete_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  delete from "better_supabase"."field_definitions" where "id" = delete_field_definition.definition;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_field_definition"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_field_definition"(uuid) to authenticated, service_role;

-- The definitions of one entity in display order.
create or replace function "better_supabase"."list_field_definitions"(tenant uuid, entity text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'rank', d."rank"
  ) order by d."rank" collate "C", d."key"), '[]'::jsonb)
  from "better_supabase"."field_definitions" d
  where d."org_id" = list_field_definitions.tenant
    and d."entity" = list_field_definitions.entity
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_field_definitions.tenant, 'custom_fields.read'), false))
$$;
revoke execute on function "better_supabase"."list_field_definitions"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_field_definitions"(uuid, text) to authenticated, service_role;

-- Sets a field's rank key, from rankBetween over its neighbours' keys.
create or replace function "better_supabase"."rank_field_definition"(definition uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_field_definition.rank is null or rank_field_definition.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'FIELD_RANK_INVALID';
  end if;
  select "org_id" into v_tenant from "better_supabase"."field_definitions" where "id" = rank_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  update "better_supabase"."field_definitions" set "rank" = rank_field_definition.rank where "id" = rank_field_definition.definition;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_field_definition"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_field_definition"(uuid, text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."field_definitions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_select on "better_supabase"."field_definitions" as restrictive
  for select to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_insert on "better_supabase"."field_definitions" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_update on "better_supabase"."field_definitions" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_delete on "better_supabase"."field_definitions" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."field_values";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_values";
create policy bsb_tenant_scope_select on "better_supabase"."field_values" as restrictive
  for select to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_values";
create policy bsb_tenant_scope_insert on "better_supabase"."field_values" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_values";
create policy bsb_tenant_scope_update on "better_supabase"."field_values" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_values";
create policy bsb_tenant_scope_delete on "better_supabase"."field_values" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block-data custom-fields
-- @bsb-hash sha256:bf98d83435a0af9b755b2461111a0962ca26ead36da48b2f14a93ede844e6d0b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('custom-fields', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
