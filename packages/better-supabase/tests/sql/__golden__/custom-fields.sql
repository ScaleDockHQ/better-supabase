-- ==== alone: schema supabase/schemas/900_better_supabase_61_custom_fields.sql
-- better-supabase module: custom-fields
-- @bs-module custom-fields@3 managed
-- Field definitions, options and typed values. A sensitive value is readable only with the field's permission. Inline layout stores the definition on the value row.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
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
    where c.conrelid = '"better_supabase"."field_definitions"'::regclass and c.conname = 'bs_field_definitions_type'
  ), 'pg_constraint'), '') <> 'better-supabase check 41e34c72' then
    alter table "better_supabase"."field_definitions" drop constraint if exists "bs_field_definitions_type";
    alter table "better_supabase"."field_definitions" add constraint "bs_field_definitions_type" check ("type" in ('text', 'number', 'date', 'bool', 'option', 'json', 'email', 'url', 'multi_option', 'user', 'rating', 'currency'));
    comment on constraint "bs_field_definitions_type" on "better_supabase"."field_definitions" is 'better-supabase check 41e34c72';
  end if;
end;
$$;
alter table "better_supabase"."field_definitions" enable row level security;
revoke all on "better_supabase"."field_definitions" from anon, authenticated;
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
revoke all on "better_supabase"."field_values" from anon, authenticated;
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
        or coalesce(better_supabase.can('tenant', v."tenant_id", coalesce(d."permission", 'custom_fields.sensitive.read')), false));
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_61_custom_fields.sql
-- better-supabase module: custom-fields
-- @bs-module-data custom-fields
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('custom-fields', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_61_custom_fields.sql
-- better-supabase module: custom-fields
-- @bs-module custom-fields@3 managed
-- Field definitions, options and typed values. A sensitive value is readable only with the field's permission. Inline layout stores the definition on the value row.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
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
    where c.conrelid = '"better_supabase"."field_definitions"'::regclass and c.conname = 'bs_field_definitions_type'
  ), 'pg_constraint'), '') <> 'better-supabase check 41e34c72' then
    alter table "better_supabase"."field_definitions" drop constraint if exists "bs_field_definitions_type";
    alter table "better_supabase"."field_definitions" add constraint "bs_field_definitions_type" check ("type" in ('text', 'number', 'date', 'bool', 'option', 'json', 'email', 'url', 'multi_option', 'user', 'rating', 'currency'));
    comment on constraint "bs_field_definitions_type" on "better_supabase"."field_definitions" is 'better-supabase check 41e34c72';
  end if;
end;
$$;
alter table "better_supabase"."field_definitions" enable row level security;
revoke all on "better_supabase"."field_definitions" from anon, authenticated;
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
revoke all on "better_supabase"."field_values" from anon, authenticated;
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
        or coalesce(better_supabase.can('tenant', v."tenant_id", coalesce(d."permission", 'custom_fields.sensitive.read')), false));
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
  if v_type not in ('text', 'email', 'url') then
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_61_custom_fields.sql
-- better-supabase module: custom-fields
-- @bs-module-data custom-fields
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('custom-fields', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_61_custom_fields.sql
-- better-supabase module: custom-fields
-- @bs-module custom-fields@3 managed
-- Field definitions, options and typed values. A sensitive value is readable only with the field's permission. Inline layout stores the definition on the value row.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
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
    where c.conrelid = '"app_private"."field_definitions"'::regclass and c.conname = 'bs_field_definitions_type'
  ), 'pg_constraint'), '') <> 'better-supabase check 41e34c72' then
    alter table "app_private"."field_definitions" drop constraint if exists "bs_field_definitions_type";
    alter table "app_private"."field_definitions" add constraint "bs_field_definitions_type" check ("type" in ('text', 'number', 'date', 'bool', 'option', 'json', 'email', 'url', 'multi_option', 'user', 'rating', 'currency'));
    comment on constraint "bs_field_definitions_type" on "app_private"."field_definitions" is 'better-supabase check 41e34c72';
  end if;
end;
$$;
alter table "app_private"."field_definitions" enable row level security;
revoke all on "app_private"."field_definitions" from anon, authenticated;
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
revoke all on "app_private"."field_values" from anon, authenticated;
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
        or coalesce(better_supabase.can('tenant', v."tenant_id", coalesce(d."permission", 'custom_fields.sensitive.read')), false));
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_61_custom_fields.sql
-- better-supabase module: custom-fields
-- @bs-module-data custom-fields
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('custom-fields', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_61_custom_fields.sql
-- better-supabase module: custom-fields
-- @bs-module custom-fields@3 managed
-- Field definitions, options and typed values. A sensitive value is readable only with the field's permission. Inline layout stores the definition on the value row.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
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
    where c.conrelid = '"better_supabase"."field_definitions"'::regclass and c.conname = 'bs_field_definitions_type'
  ), 'pg_constraint'), '') <> 'better-supabase check 41e34c72' then
    alter table "better_supabase"."field_definitions" drop constraint if exists "bs_field_definitions_type";
    alter table "better_supabase"."field_definitions" add constraint "bs_field_definitions_type" check ("type" in ('text', 'number', 'date', 'bool', 'option', 'json', 'email', 'url', 'multi_option', 'user', 'rating', 'currency'));
    comment on constraint "bs_field_definitions_type" on "better_supabase"."field_definitions" is 'better-supabase check 41e34c72';
  end if;
end;
$$;
alter table "better_supabase"."field_definitions" enable row level security;
revoke all on "better_supabase"."field_definitions" from anon, authenticated;
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
revoke all on "better_supabase"."field_values" from anon, authenticated;
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
        or coalesce(better_supabase.can('tenant', v."tenant_id", coalesce(d."permission", 'custom_fields.sensitive.read')), false));
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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_61_custom_fields.sql
-- better-supabase module: custom-fields
-- @bs-module-data custom-fields
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('custom-fields', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== adopt: schema supabase/schemas/900_better_supabase_61_custom_fields.sql
-- better-supabase module: custom-fields
-- @bs-module custom-fields@3 adopt
-- Field definitions, options and typed values. A sensitive value is readable only with the field's permission. Inline layout stores the definition on the value row.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- A sensitive value is returned only when the caller holds the field's
-- permission, or custom_fields.sensitive.read when the field names none.

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
        or coalesce(better_supabase.can('tenant', v."tenant_id", coalesce(d."permission", 'custom_fields.sensitive.read')), false));
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

-- ==== adopt: data supabase/better-supabase-data/900_better_supabase_61_custom_fields.sql
-- better-supabase module: custom-fields
-- @bs-module-data custom-fields
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('custom-fields', 3, 'adopt')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
