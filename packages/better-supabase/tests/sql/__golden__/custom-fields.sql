-- ==== alone: schema supabase/schemas/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block custom-fields@4 managed
-- @bsb-hash sha256:323745d13a5b37808617cc294a58ada6287f87eadf8545efcd2e53e7683d81bf
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
  "pack" text,
  "pack_version" integer,
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
  v_inserted boolean;
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
  returning "id", xmax = 0 into v_id, v_inserted;
  if v_inserted then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) to authenticated, service_role;

drop function if exists "better_supabase"."read_field_values"(uuid, text, text, uuid);
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

drop function if exists "better_supabase"."set_field_value"(uuid, text, text, uuid, text, uuid);
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
    'pack', d."pack",
    'packVersion', d."pack_version",
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

-- Installs a field pack (apiVersion 1): { key, version, subjects: { <type>:
-- [{ key, label, type, required?, sensitive?, permission? }] } }. A definition
-- is matched by (pack, key), so a second install changes nothing.
create or replace function "better_supabase"."install_field_pack"(tenant uuid, pack jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_key text := install_field_pack.pack ->> 'key';
  v_version integer;
  v_entity text;
  v_fields jsonb;
  v_field jsonb;
  v_field_key text;
  v_label text;
  v_type text;
  v_required boolean;
  v_sensitive boolean;
  v_permission text;
  v_row record;
  v_id uuid;
  v_last text;
  v_rank text;
  v_created integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', install_field_pack.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if jsonb_typeof(install_field_pack.pack) is distinct from 'object' or install_field_pack.pack ->> 'apiVersion' is distinct from '1' then
    raise exception 'a field pack is an object with apiVersion 1' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  if v_key is null or v_key !~ '^[a-z][a-z0-9_.-]{0,62}$' then
    raise exception 'a field pack needs a key in lower case' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  begin
    v_version := (install_field_pack.pack ->> 'version')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    v_version := null;
  end;
  if v_version is null or v_version < 1 then
    raise exception 'a field pack needs a version of 1 or more' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  if jsonb_typeof(install_field_pack.pack -> 'subjects') is distinct from 'object' then
    raise exception 'a field pack needs subjects: { <type>: fields }' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;

  for v_entity, v_fields in select s.key, s.value from jsonb_each(install_field_pack.pack -> 'subjects') s order by s.key loop
    
    if jsonb_typeof(v_fields) is distinct from 'array' then
      raise exception 'the fields of a subject type are a list' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
    end if;
    for v_field in select f.value from jsonb_array_elements(v_fields) f loop
      if jsonb_typeof(v_field) is distinct from 'object' then
        raise exception 'a field is an object of key, label and type' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      v_field_key := v_field ->> 'key';
      v_label := v_field ->> 'label';
      v_type := v_field ->> 'type';
      v_permission := nullif(v_field ->> 'permission', '');
      if v_field_key is null or v_field_key !~ '^[a-z][a-z0-9_.-]{0,62}$' or v_label is null or btrim(v_label) = '' then
        raise exception 'a field needs a key in lower case and a label' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      if v_type is null or v_type not in ('text', 'number', 'date', 'bool', 'option', 'json', 'email', 'url', 'multi_option', 'user', 'rating', 'currency', 'bsn', 'iban', 'phone_e164') then
        raise exception 'a field needs one of the custom field types' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      if (v_field ? 'required' and jsonb_typeof(v_field -> 'required') <> 'boolean') or (v_field ? 'sensitive' and jsonb_typeof(v_field -> 'sensitive') <> 'boolean') then
        raise exception 'required and sensitive are booleans' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      v_required := coalesce((v_field ->> 'required')::boolean, false);
      v_sensitive := coalesce((v_field ->> 'sensitive')::boolean, false);

      select d."id" as id, d."pack" as pack, d."pack_version" as version, d."label" as label, d."type" as type,
        d."required" as required, d."sensitive" as sensitive, d."permission" as permission
      into v_row
      from "better_supabase"."field_definitions" d
      where d."tenant_id" = install_field_pack.tenant and d."entity" = v_entity and d."key" = v_field_key;

      if not found then
        select max(d."rank" collate "C") into v_last from "better_supabase"."field_definitions" d
        where d."tenant_id" = install_field_pack.tenant and d."entity" = v_entity;
        v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
        insert into "better_supabase"."field_definitions" ("tenant_id", "entity", "key", "label", "type", "required", "sensitive", "permission", "pack", "pack_version", "rank")
        values (install_field_pack.tenant, v_entity, v_field_key, v_label, v_type, v_required, v_sensitive, v_permission, v_key, v_version, v_rank)
        returning "id" into v_id;
        v_created := v_created + 1;
        null;
      elsif v_row.pack is distinct from v_key then
        raise exception 'the field already exists and doesn''t belong to this pack' using errcode = '23505', hint = 'FIELD_PACK_CONFLICT';
      elsif v_row.label = v_label and v_row.type = v_type and v_row.required = v_required and v_row.sensitive = v_sensitive
        and v_row.permission is not distinct from v_permission and v_row.version is not distinct from v_version then
        v_unchanged := v_unchanged + 1;
      else
        update "better_supabase"."field_definitions" set "label" = v_label, "type" = v_type, "required" = v_required, "sensitive" = v_sensitive,
          "permission" = v_permission, "pack_version" = v_version
        where "id" = v_row.id;
        v_updated := v_updated + 1;
        null;
      end if;
    end loop;
  end loop;
  return jsonb_build_object('pack', v_key, 'version', v_version, 'created', v_created, 'updated', v_updated, 'unchanged', v_unchanged);
end;
$$;
revoke execute on function "better_supabase"."install_field_pack"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."install_field_pack"(uuid, jsonb) to authenticated, service_role;

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
-- @bsb-hash sha256:2f372e03cc31a3775142510e905c3eac5585015d0adfc00b13e88d16eeb1e378
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('custom-fields', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block custom-fields@4 managed
-- @bsb-hash sha256:82b527f2672483bf2420c9331f4c1ae9d93205d9bd307d3b08f491d1bd709889
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
  "pack" text,
  "pack_version" integer,
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
  v_inserted boolean;
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
  returning "id", xmax = 0 into v_id, v_inserted;
  if v_inserted then
    perform "better_supabase".emit_event('field_definition.created', jsonb_build_object('organizationId', save_field_definition.tenant, 'id', v_id, 'entity', save_field_definition.entity), 'custom-fields/' || coalesce(v_id::text, save_field_definition.key), (save_field_definition.tenant)::text, null, 'better-supabase/custom-fields');
  else
    perform "better_supabase".emit_event('field_definition.updated', jsonb_build_object('organizationId', save_field_definition.tenant, 'id', v_id, 'entity', save_field_definition.entity), 'custom-fields/' || coalesce(v_id::text, save_field_definition.key), (save_field_definition.tenant)::text, null, 'better-supabase/custom-fields');
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) to authenticated, service_role;

drop function if exists "better_supabase"."read_field_values"(uuid, text, text);
create or replace function "better_supabase"."read_field_values"(tenant uuid, subject_type text, subject_id text, legal_entity uuid default null)
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
  from (select distinct on (x."definition_id") x.* from "better_supabase"."field_values" x
    where x."tenant_id" = read_field_values.tenant
      and x."subject_type" = read_field_values.subject_type
      and x."subject_id" = read_field_values.subject_id
      and (x.legal_entity_id is null or x.legal_entity_id = read_field_values.legal_entity)
    order by x."definition_id", x.legal_entity_id nulls last) v
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
revoke execute on function "better_supabase"."read_field_values"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."read_field_values"(uuid, text, text, uuid) to authenticated, service_role;

drop function if exists "better_supabase"."set_field_value"(uuid, text, text, uuid, text);
create or replace function "better_supabase"."set_field_value"(tenant uuid, subject_type text, subject_id text, definition uuid, value text, legal_entity uuid default null)
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
  insert into "better_supabase"."field_values" ("tenant_id", "definition_id", "subject_type", "subject_id", "value_text", legal_entity_id)
  values (set_field_value.tenant, set_field_value.definition, set_field_value.subject_type, set_field_value.subject_id, case when exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and d."encrypted") then "better_supabase"."field_encrypt"('tenant:' || set_field_value.tenant::text, set_field_value.value) else set_field_value.value end, set_field_value.legal_entity)
  returning "id" into v_id;
  perform "better_supabase".emit_event('field_value.set', jsonb_build_object('organizationId', set_field_value.tenant, 'id', v_id, 'subjectType', set_field_value.subject_type, 'subjectId', set_field_value.subject_id), 'field-values/' || v_id::text, (set_field_value.tenant)::text, null, 'better-supabase/custom-fields');
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."set_field_value"(uuid, text, text, uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."set_field_value"(uuid, text, text, uuid, text, uuid) to authenticated, service_role;

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
  perform "better_supabase".emit_event('field_definition.deleted', jsonb_build_object('organizationId', v_tenant, 'id', delete_field_definition.definition), 'custom-fields/' || delete_field_definition.definition::text, (v_tenant)::text, null, 'better-supabase/custom-fields');
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
    'pack', d."pack",
    'packVersion', d."pack_version",
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

-- Installs a field pack (apiVersion 1): { key, version, subjects: { <type>:
-- [{ key, label, type, required?, sensitive?, permission? }] } }. A definition
-- is matched by (pack, key), so a second install changes nothing.
create or replace function "better_supabase"."install_field_pack"(tenant uuid, pack jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_key text := install_field_pack.pack ->> 'key';
  v_version integer;
  v_entity text;
  v_fields jsonb;
  v_field jsonb;
  v_field_key text;
  v_label text;
  v_type text;
  v_required boolean;
  v_sensitive boolean;
  v_permission text;
  v_row record;
  v_id uuid;
  v_last text;
  v_rank text;
  v_created integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', install_field_pack.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if jsonb_typeof(install_field_pack.pack) is distinct from 'object' or install_field_pack.pack ->> 'apiVersion' is distinct from '1' then
    raise exception 'a field pack is an object with apiVersion 1' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  if v_key is null or v_key !~ '^[a-z][a-z0-9_.-]{0,62}$' then
    raise exception 'a field pack needs a key in lower case' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  begin
    v_version := (install_field_pack.pack ->> 'version')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    v_version := null;
  end;
  if v_version is null or v_version < 1 then
    raise exception 'a field pack needs a version of 1 or more' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  if jsonb_typeof(install_field_pack.pack -> 'subjects') is distinct from 'object' then
    raise exception 'a field pack needs subjects: { <type>: fields }' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;

  for v_entity, v_fields in select s.key, s.value from jsonb_each(install_field_pack.pack -> 'subjects') s order by s.key loop
    
    if jsonb_typeof(v_fields) is distinct from 'array' then
      raise exception 'the fields of a subject type are a list' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
    end if;
    for v_field in select f.value from jsonb_array_elements(v_fields) f loop
      if jsonb_typeof(v_field) is distinct from 'object' then
        raise exception 'a field is an object of key, label and type' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      v_field_key := v_field ->> 'key';
      v_label := v_field ->> 'label';
      v_type := v_field ->> 'type';
      v_permission := nullif(v_field ->> 'permission', '');
      if v_field_key is null or v_field_key !~ '^[a-z][a-z0-9_.-]{0,62}$' or v_label is null or btrim(v_label) = '' then
        raise exception 'a field needs a key in lower case and a label' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      if v_type is null or v_type not in ('text', 'number', 'date', 'bool', 'option', 'json', 'email', 'url', 'multi_option', 'user', 'rating', 'currency', 'bsn', 'iban', 'phone_e164') then
        raise exception 'a field needs one of the custom field types' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      if (v_field ? 'required' and jsonb_typeof(v_field -> 'required') <> 'boolean') or (v_field ? 'sensitive' and jsonb_typeof(v_field -> 'sensitive') <> 'boolean') then
        raise exception 'required and sensitive are booleans' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      v_required := coalesce((v_field ->> 'required')::boolean, false);
      v_sensitive := coalesce((v_field ->> 'sensitive')::boolean, false);

      select d."id" as id, d."pack" as pack, d."pack_version" as version, d."label" as label, d."type" as type,
        d."required" as required, d."sensitive" as sensitive, d."permission" as permission
      into v_row
      from "better_supabase"."field_definitions" d
      where d."tenant_id" = install_field_pack.tenant and d."entity" = v_entity and d."key" = v_field_key;

      if not found then
        select max(d."rank" collate "C") into v_last from "better_supabase"."field_definitions" d
        where d."tenant_id" = install_field_pack.tenant and d."entity" = v_entity;
        v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
        insert into "better_supabase"."field_definitions" ("tenant_id", "entity", "key", "label", "type", "required", "sensitive", "permission", "pack", "pack_version", "rank")
        values (install_field_pack.tenant, v_entity, v_field_key, v_label, v_type, v_required, v_sensitive, v_permission, v_key, v_version, v_rank)
        returning "id" into v_id;
        v_created := v_created + 1;
        perform "better_supabase".emit_event('field_definition.created', jsonb_build_object('organizationId', install_field_pack.tenant, 'id', v_id, 'entity', v_entity), 'custom-fields/' || v_id::text, (install_field_pack.tenant)::text, null, 'better-supabase/custom-fields');
      elsif v_row.pack is distinct from v_key then
        raise exception 'the field already exists and doesn''t belong to this pack' using errcode = '23505', hint = 'FIELD_PACK_CONFLICT';
      elsif v_row.label = v_label and v_row.type = v_type and v_row.required = v_required and v_row.sensitive = v_sensitive
        and v_row.permission is not distinct from v_permission and v_row.version is not distinct from v_version then
        v_unchanged := v_unchanged + 1;
      else
        update "better_supabase"."field_definitions" set "label" = v_label, "type" = v_type, "required" = v_required, "sensitive" = v_sensitive,
          "permission" = v_permission, "pack_version" = v_version
        where "id" = v_row.id;
        v_updated := v_updated + 1;
        perform "better_supabase".emit_event('field_definition.updated', jsonb_build_object('organizationId', install_field_pack.tenant, 'id', v_row.id, 'entity', v_entity), 'custom-fields/' || v_row.id::text, (install_field_pack.tenant)::text, null, 'better-supabase/custom-fields');
      end if;
    end loop;
  end loop;
  return jsonb_build_object('pack', v_key, 'version', v_version, 'created', v_created, 'updated', v_updated, 'unchanged', v_unchanged);
end;
$$;
revoke execute on function "better_supabase"."install_field_pack"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."install_field_pack"(uuid, jsonb) to authenticated, service_role;

-- The import target of the field_value entity (ADR 0156). A subject is named by
-- its external key in the run's source, so the value follows the record the
-- import record map holds.
create or replace function "better_supabase"."import_field_value"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid := (import_field_value.item ->> 'tenant')::uuid;
  v_scope text := coalesce(import_field_value.item ->> 'scope', '');
  v_data jsonb := import_field_value.item -> 'data';
  v_reference jsonb := v_data -> 'subject';
  v_type text := nullif(v_data ->> 'subjectType', '');
  v_subject text := nullif(v_data ->> 'subjectId', '');
  v_field text := v_data ->> 'field';
  v_value text;
  v_definition uuid;
  v_field_type text;
  v_entity uuid;
  v_row uuid;
begin
  if jsonb_typeof(v_data -> 'value') in ('object', 'array', 'null') or (v_data -> 'value') is null then
    raise exception 'a field value needs a value of text, a number or a boolean' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_value := v_data ->> 'value';
  if v_field is null or v_field = '' then
    raise exception 'a field value needs the key of its field' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_entity := nullif(v_data ->> 'legalEntityId', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'legalEntityId must be a uuid' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_reference is not null then
    if jsonb_typeof(v_reference) is distinct from 'object' then
      raise exception 'subject is { entity, key }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    select x."subject_type", x."subject_id" into v_type, v_subject
    from "better_supabase"."import_records" x
    join "better_supabase"."import_runs" u on u."id" = import_field_value.run
    where x."tenant_id" = v_tenant and x."source" = u."source"
      and x."scope" = v_scope
      and x."entity" = v_reference ->> 'entity' and x."external_key" = v_reference ->> 'key'
      and x."role" = 'primary';
    if not found then
      raise exception 'the record isn''t in the import record map; import it first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
  end if;
  if v_type is null or v_subject is null then
    raise exception 'a field value needs a subject: { entity, key }, or subjectType and subjectId' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  
  select d."id", d."type" into v_definition, v_field_type
  from "better_supabase"."field_definitions" d
  where d."tenant_id" = v_tenant and d."entity" = v_type and d."key" = v_field;
  if not found then
    raise exception 'no field definition with this key on the subject type' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if not (case v_field_type when 'bsn' then "better_supabase"."bsb_valid_bsn"(v_value) when 'iban' then "better_supabase"."bsb_valid_iban"(v_value) when 'phone_e164' then v_value ~* '^\+[1-9][0-9]{1,14}$' else true end) then
    raise exception 'the value doesn''t match the field''s format' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  select y."id" into v_row from "better_supabase"."field_values" y
  where y."tenant_id" = v_tenant and y."subject_type" = v_type and y."subject_id" = v_subject and y."definition_id" = v_definition
    and coalesce(y.legal_entity_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_entity, '00000000-0000-0000-0000-000000000000'::uuid);
  if found then
    update "better_supabase"."field_values" set "value_text" = case when exists (select 1 from "better_supabase"."field_definitions" d where d."id" = v_definition and d."encrypted") then "better_supabase"."field_encrypt"('tenant:' || v_tenant::text, v_value) else v_value end where "id" = v_row;
  else
    insert into "better_supabase"."field_values" ("tenant_id", "definition_id", "subject_type", "subject_id", "value_text", legal_entity_id)
    values (v_tenant, v_definition, v_type, v_subject, case when exists (select 1 from "better_supabase"."field_definitions" d where d."id" = v_definition and d."encrypted") then "better_supabase"."field_encrypt"('tenant:' || v_tenant::text, v_value) else v_value end, v_entity)
    returning "id" into v_row;
  end if;
  perform "better_supabase".emit_event('field_value.set', jsonb_build_object('organizationId', v_tenant, 'id', v_row, 'subjectType', v_type, 'subjectId', v_subject), 'field-values/' || v_row::text, (v_tenant)::text, null, 'better-supabase/custom-fields');
  return jsonb_build_object('subjectId', v_row::text, 'subjectType', 'field_value');
end;
$$;
revoke execute on function "better_supabase"."import_field_value"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_field_value"(uuid, jsonb, text) to service_role;

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

-- Row audit for the module's tables (blocks.audit.options.blockTables)
do $$
begin
  perform better_supabase.audit('better_supabase.field_definitions', target_type => 'field_definition', event_prefix => 'field_definition', deferred => true);
end;
$$;

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
-- @bsb-hash sha256:2f372e03cc31a3775142510e905c3eac5585015d0adfc00b13e88d16eeb1e378
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('custom-fields', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block custom-fields@4 managed
-- @bsb-hash sha256:b560e57d45cb32ee12feaa12bb234a7448961b14a8265f52e99f76ca38256f90
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
  "pack" text,
  "pack_version" integer,
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
  v_inserted boolean;
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
  returning "id", xmax = 0 into v_id, v_inserted;
  if v_inserted then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "app_private"."save_field_definition"(uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "app_private"."save_field_definition"(uuid, text, text, text, text, boolean) to authenticated, service_role;

drop function if exists "app_private"."read_field_values"(uuid, text, text, uuid);
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

drop function if exists "app_private"."set_field_value"(uuid, text, text, uuid, text, uuid);
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
    'pack', d."pack",
    'packVersion', d."pack_version",
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

-- Installs a field pack (apiVersion 1): { key, version, subjects: { <type>:
-- [{ key, label, type, required?, sensitive?, permission? }] } }. A definition
-- is matched by (pack, key), so a second install changes nothing.
create or replace function "app_private"."install_field_pack"(tenant uuid, pack jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_key text := install_field_pack.pack ->> 'key';
  v_version integer;
  v_entity text;
  v_fields jsonb;
  v_field jsonb;
  v_field_key text;
  v_label text;
  v_type text;
  v_required boolean;
  v_sensitive boolean;
  v_permission text;
  v_row record;
  v_id uuid;
  v_last text;
  v_rank text;
  v_created integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', install_field_pack.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if jsonb_typeof(install_field_pack.pack) is distinct from 'object' or install_field_pack.pack ->> 'apiVersion' is distinct from '1' then
    raise exception 'a field pack is an object with apiVersion 1' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  if v_key is null or v_key !~ '^[a-z][a-z0-9_.-]{0,62}$' then
    raise exception 'a field pack needs a key in lower case' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  begin
    v_version := (install_field_pack.pack ->> 'version')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    v_version := null;
  end;
  if v_version is null or v_version < 1 then
    raise exception 'a field pack needs a version of 1 or more' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  if jsonb_typeof(install_field_pack.pack -> 'subjects') is distinct from 'object' then
    raise exception 'a field pack needs subjects: { <type>: fields }' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;

  for v_entity, v_fields in select s.key, s.value from jsonb_each(install_field_pack.pack -> 'subjects') s order by s.key loop
    
    if jsonb_typeof(v_fields) is distinct from 'array' then
      raise exception 'the fields of a subject type are a list' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
    end if;
    for v_field in select f.value from jsonb_array_elements(v_fields) f loop
      if jsonb_typeof(v_field) is distinct from 'object' then
        raise exception 'a field is an object of key, label and type' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      v_field_key := v_field ->> 'key';
      v_label := v_field ->> 'label';
      v_type := v_field ->> 'type';
      v_permission := nullif(v_field ->> 'permission', '');
      if v_field_key is null or v_field_key !~ '^[a-z][a-z0-9_.-]{0,62}$' or v_label is null or btrim(v_label) = '' then
        raise exception 'a field needs a key in lower case and a label' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      if v_type is null or v_type not in ('text', 'number', 'date', 'bool', 'option', 'json', 'email', 'url', 'multi_option', 'user', 'rating', 'currency', 'bsn', 'iban', 'phone_e164') then
        raise exception 'a field needs one of the custom field types' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      if (v_field ? 'required' and jsonb_typeof(v_field -> 'required') <> 'boolean') or (v_field ? 'sensitive' and jsonb_typeof(v_field -> 'sensitive') <> 'boolean') then
        raise exception 'required and sensitive are booleans' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      v_required := coalesce((v_field ->> 'required')::boolean, false);
      v_sensitive := coalesce((v_field ->> 'sensitive')::boolean, false);

      select d."id" as id, d."pack" as pack, d."pack_version" as version, d."label" as label, d."type" as type,
        d."required" as required, d."sensitive" as sensitive, d."permission" as permission
      into v_row
      from "app_private"."field_definitions" d
      where d."tenant_id" = install_field_pack.tenant and d."entity" = v_entity and d."key" = v_field_key;

      if not found then
        select max(d."rank" collate "C") into v_last from "app_private"."field_definitions" d
        where d."tenant_id" = install_field_pack.tenant and d."entity" = v_entity;
        v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
        insert into "app_private"."field_definitions" ("tenant_id", "entity", "key", "label", "type", "required", "sensitive", "permission", "pack", "pack_version", "rank")
        values (install_field_pack.tenant, v_entity, v_field_key, v_label, v_type, v_required, v_sensitive, v_permission, v_key, v_version, v_rank)
        returning "id" into v_id;
        v_created := v_created + 1;
        null;
      elsif v_row.pack is distinct from v_key then
        raise exception 'the field already exists and doesn''t belong to this pack' using errcode = '23505', hint = 'FIELD_PACK_CONFLICT';
      elsif v_row.label = v_label and v_row.type = v_type and v_row.required = v_required and v_row.sensitive = v_sensitive
        and v_row.permission is not distinct from v_permission and v_row.version is not distinct from v_version then
        v_unchanged := v_unchanged + 1;
      else
        update "app_private"."field_definitions" set "label" = v_label, "type" = v_type, "required" = v_required, "sensitive" = v_sensitive,
          "permission" = v_permission, "pack_version" = v_version
        where "id" = v_row.id;
        v_updated := v_updated + 1;
        null;
      end if;
    end loop;
  end loop;
  return jsonb_build_object('pack', v_key, 'version', v_version, 'created', v_created, 'updated', v_updated, 'unchanged', v_unchanged);
end;
$$;
revoke execute on function "app_private"."install_field_pack"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."install_field_pack"(uuid, jsonb) to authenticated, service_role;

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
-- @bsb-hash sha256:2f372e03cc31a3775142510e905c3eac5585015d0adfc00b13e88d16eeb1e378
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('custom-fields', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block custom-fields@4 managed
-- @bsb-hash sha256:7a03ea52da4da8e22a91d5ff319629bba2831a6a506d571a462e6c2d392b22c2
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
  "pack" text,
  "pack_version" integer,
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
  v_inserted boolean;
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
  returning "id", xmax = 0 into v_id, v_inserted;
  if v_inserted then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) to authenticated, service_role;

drop function if exists "better_supabase"."read_field_values"(uuid, text, text, uuid);
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

drop function if exists "better_supabase"."set_field_value"(uuid, text, text, uuid, text, uuid);
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
    'pack', d."pack",
    'packVersion', d."pack_version",
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

-- Installs a field pack (apiVersion 1): { key, version, subjects: { <type>:
-- [{ key, label, type, required?, sensitive?, permission? }] } }. A definition
-- is matched by (pack, key), so a second install changes nothing.
create or replace function "better_supabase"."install_field_pack"(tenant uuid, pack jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_key text := install_field_pack.pack ->> 'key';
  v_version integer;
  v_entity text;
  v_fields jsonb;
  v_field jsonb;
  v_field_key text;
  v_label text;
  v_type text;
  v_required boolean;
  v_sensitive boolean;
  v_permission text;
  v_row record;
  v_id uuid;
  v_last text;
  v_rank text;
  v_created integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', install_field_pack.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if jsonb_typeof(install_field_pack.pack) is distinct from 'object' or install_field_pack.pack ->> 'apiVersion' is distinct from '1' then
    raise exception 'a field pack is an object with apiVersion 1' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  if v_key is null or v_key !~ '^[a-z][a-z0-9_.-]{0,62}$' then
    raise exception 'a field pack needs a key in lower case' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  begin
    v_version := (install_field_pack.pack ->> 'version')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    v_version := null;
  end;
  if v_version is null or v_version < 1 then
    raise exception 'a field pack needs a version of 1 or more' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  if jsonb_typeof(install_field_pack.pack -> 'subjects') is distinct from 'object' then
    raise exception 'a field pack needs subjects: { <type>: fields }' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;

  for v_entity, v_fields in select s.key, s.value from jsonb_each(install_field_pack.pack -> 'subjects') s order by s.key loop
    
    if jsonb_typeof(v_fields) is distinct from 'array' then
      raise exception 'the fields of a subject type are a list' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
    end if;
    for v_field in select f.value from jsonb_array_elements(v_fields) f loop
      if jsonb_typeof(v_field) is distinct from 'object' then
        raise exception 'a field is an object of key, label and type' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      v_field_key := v_field ->> 'key';
      v_label := v_field ->> 'label';
      v_type := v_field ->> 'type';
      v_permission := nullif(v_field ->> 'permission', '');
      if v_field_key is null or v_field_key !~ '^[a-z][a-z0-9_.-]{0,62}$' or v_label is null or btrim(v_label) = '' then
        raise exception 'a field needs a key in lower case and a label' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      if v_type is null or v_type not in ('text', 'number', 'date', 'bool', 'option', 'json', 'email', 'url', 'multi_option', 'user', 'rating', 'currency', 'bsn', 'iban', 'phone_e164') then
        raise exception 'a field needs one of the custom field types' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      if (v_field ? 'required' and jsonb_typeof(v_field -> 'required') <> 'boolean') or (v_field ? 'sensitive' and jsonb_typeof(v_field -> 'sensitive') <> 'boolean') then
        raise exception 'required and sensitive are booleans' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      v_required := coalesce((v_field ->> 'required')::boolean, false);
      v_sensitive := coalesce((v_field ->> 'sensitive')::boolean, false);

      select d."id" as id, d."pack" as pack, d."pack_version" as version, d."label" as label, d."type" as type,
        d."required" as required, d."sensitive" as sensitive, d."permission" as permission
      into v_row
      from "better_supabase"."field_definitions" d
      where d."tenant_id" = install_field_pack.tenant and d."entity" = v_entity and d."key" = v_field_key;

      if not found then
        select max(d."rank" collate "C") into v_last from "better_supabase"."field_definitions" d
        where d."tenant_id" = install_field_pack.tenant and d."entity" = v_entity;
        v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
        insert into "better_supabase"."field_definitions" ("tenant_id", "entity", "key", "label", "type", "required", "sensitive", "permission", "pack", "pack_version", "rank")
        values (install_field_pack.tenant, v_entity, v_field_key, v_label, v_type, v_required, v_sensitive, v_permission, v_key, v_version, v_rank)
        returning "id" into v_id;
        v_created := v_created + 1;
        null;
      elsif v_row.pack is distinct from v_key then
        raise exception 'the field already exists and doesn''t belong to this pack' using errcode = '23505', hint = 'FIELD_PACK_CONFLICT';
      elsif v_row.label = v_label and v_row.type = v_type and v_row.required = v_required and v_row.sensitive = v_sensitive
        and v_row.permission is not distinct from v_permission and v_row.version is not distinct from v_version then
        v_unchanged := v_unchanged + 1;
      else
        update "better_supabase"."field_definitions" set "label" = v_label, "type" = v_type, "required" = v_required, "sensitive" = v_sensitive,
          "permission" = v_permission, "pack_version" = v_version
        where "id" = v_row.id;
        v_updated := v_updated + 1;
        null;
      end if;
    end loop;
  end loop;
  return jsonb_build_object('pack', v_key, 'version', v_version, 'created', v_created, 'updated', v_updated, 'unchanged', v_unchanged);
end;
$$;
revoke execute on function "better_supabase"."install_field_pack"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."install_field_pack"(uuid, jsonb) to authenticated, service_role;

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

drop function if exists "api"."read_field_values"(uuid, text, text, uuid);
drop function if exists "api"."set_field_value"(uuid, text, text, uuid, text, uuid);

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

create or replace function "api"."install_field_pack"(tenant uuid, pack jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."install_field_pack"($1, $2) $$;
revoke execute on function "api"."install_field_pack"(uuid, jsonb) from public, anon;
grant execute on function "api"."install_field_pack"(uuid, jsonb) to authenticated, service_role;

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
-- @bsb-hash sha256:2f372e03cc31a3775142510e905c3eac5585015d0adfc00b13e88d16eeb1e378
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('custom-fields', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block custom-fields@4 managed
-- @bsb-hash sha256:f8f077be32bb8a03500eb152b34a3ec364b32a149b44c75ad73380933b47db40
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
alter table "better_supabase"."field_definitions" add column if not exists "pack" text;
alter table "better_supabase"."field_definitions" add column if not exists "pack_version" integer;
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
  v_inserted boolean;
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
  returning "id", xmax = 0 into v_id, v_inserted;
  if v_inserted then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) to authenticated, service_role;

drop function if exists "better_supabase"."read_field_values"(uuid, text, text, uuid);
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

drop function if exists "better_supabase"."set_field_value"(uuid, text, text, uuid, text, uuid);
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
    'pack', d."pack",
    'packVersion', d."pack_version",
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

-- Installs a field pack (apiVersion 1): { key, version, subjects: { <type>:
-- [{ key, label, type, required?, sensitive?, permission? }] } }. A definition
-- is matched by (pack, key), so a second install changes nothing.
create or replace function "better_supabase"."install_field_pack"(tenant uuid, pack jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_key text := install_field_pack.pack ->> 'key';
  v_version integer;
  v_entity text;
  v_fields jsonb;
  v_field jsonb;
  v_field_key text;
  v_label text;
  v_type text;
  v_required boolean;
  v_sensitive boolean;
  v_permission text;
  v_row record;
  v_id uuid;
  v_last text;
  v_rank text;
  v_created integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', install_field_pack.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if jsonb_typeof(install_field_pack.pack) is distinct from 'object' or install_field_pack.pack ->> 'apiVersion' is distinct from '1' then
    raise exception 'a field pack is an object with apiVersion 1' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  if v_key is null or v_key !~ '^[a-z][a-z0-9_.-]{0,62}$' then
    raise exception 'a field pack needs a key in lower case' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  begin
    v_version := (install_field_pack.pack ->> 'version')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    v_version := null;
  end;
  if v_version is null or v_version < 1 then
    raise exception 'a field pack needs a version of 1 or more' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  if jsonb_typeof(install_field_pack.pack -> 'subjects') is distinct from 'object' then
    raise exception 'a field pack needs subjects: { <type>: fields }' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;

  for v_entity, v_fields in select s.key, s.value from jsonb_each(install_field_pack.pack -> 'subjects') s order by s.key loop
    
    if jsonb_typeof(v_fields) is distinct from 'array' then
      raise exception 'the fields of a subject type are a list' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
    end if;
    for v_field in select f.value from jsonb_array_elements(v_fields) f loop
      if jsonb_typeof(v_field) is distinct from 'object' then
        raise exception 'a field is an object of key, label and type' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      v_field_key := v_field ->> 'key';
      v_label := v_field ->> 'label';
      v_type := v_field ->> 'type';
      v_permission := nullif(v_field ->> 'permission', '');
      if v_field_key is null or v_field_key !~ '^[a-z][a-z0-9_.-]{0,62}$' or v_label is null or btrim(v_label) = '' then
        raise exception 'a field needs a key in lower case and a label' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      if v_type is null or v_type not in ('text', 'number', 'date', 'bool', 'option', 'json', 'email', 'url', 'multi_option', 'user', 'rating', 'currency', 'bsn', 'iban', 'phone_e164') then
        raise exception 'a field needs one of the custom field types' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      if (v_field ? 'required' and jsonb_typeof(v_field -> 'required') <> 'boolean') or (v_field ? 'sensitive' and jsonb_typeof(v_field -> 'sensitive') <> 'boolean') then
        raise exception 'required and sensitive are booleans' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      v_required := coalesce((v_field ->> 'required')::boolean, false);
      v_sensitive := coalesce((v_field ->> 'sensitive')::boolean, false);

      select d."id" as id, d."pack" as pack, d."pack_version" as version, d."label" as label, d."type" as type,
        d."required" as required, d."sensitive" as sensitive, d."permission" as permission
      into v_row
      from "better_supabase"."field_definitions" d
      where d."tenant_id" = install_field_pack.tenant and d."entity" = v_entity and d."key" = v_field_key;

      if not found then
        select max(d."rank" collate "C") into v_last from "better_supabase"."field_definitions" d
        where d."tenant_id" = install_field_pack.tenant and d."entity" = v_entity;
        v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
        insert into "better_supabase"."field_definitions" ("tenant_id", "entity", "key", "label", "type", "required", "sensitive", "permission", "pack", "pack_version", "rank")
        values (install_field_pack.tenant, v_entity, v_field_key, v_label, v_type, v_required, v_sensitive, v_permission, v_key, v_version, v_rank)
        returning "id" into v_id;
        v_created := v_created + 1;
        null;
      elsif v_row.pack is distinct from v_key then
        raise exception 'the field already exists and doesn''t belong to this pack' using errcode = '23505', hint = 'FIELD_PACK_CONFLICT';
      elsif v_row.label = v_label and v_row.type = v_type and v_row.required = v_required and v_row.sensitive = v_sensitive
        and v_row.permission is not distinct from v_permission and v_row.version is not distinct from v_version then
        v_unchanged := v_unchanged + 1;
      else
        update "better_supabase"."field_definitions" set "label" = v_label, "type" = v_type, "required" = v_required, "sensitive" = v_sensitive,
          "permission" = v_permission, "pack_version" = v_version
        where "id" = v_row.id;
        v_updated := v_updated + 1;
        null;
      end if;
    end loop;
  end loop;
  return jsonb_build_object('pack', v_key, 'version', v_version, 'created', v_created, 'updated', v_updated, 'unchanged', v_unchanged);
end;
$$;
revoke execute on function "better_supabase"."install_field_pack"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."install_field_pack"(uuid, jsonb) to authenticated, service_role;

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
-- @bsb-hash sha256:2f372e03cc31a3775142510e905c3eac5585015d0adfc00b13e88d16eeb1e378
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('custom-fields', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block custom-fields@4 managed
-- @bsb-hash sha256:4f6c75b8eafeaba9c3a6bd48fd1f62689ecf7b0d4f8425c42b8bb016c803b5b5
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
  "pack" text,
  "pack_version" integer,
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
  v_inserted boolean;
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
  returning "id", xmax = 0 into v_id, v_inserted;
  if v_inserted then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_field_definition"(uuid, text, text, text, text, boolean) to authenticated, service_role;

drop function if exists "better_supabase"."read_field_values"(uuid, text, text, uuid);
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

drop function if exists "better_supabase"."set_field_value"(uuid, text, text, uuid, text, uuid);
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
    'pack', d."pack",
    'packVersion', d."pack_version",
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

-- Installs a field pack (apiVersion 1): { key, version, subjects: { <type>:
-- [{ key, label, type, required?, sensitive?, permission? }] } }. A definition
-- is matched by (pack, key), so a second install changes nothing.
create or replace function "better_supabase"."install_field_pack"(tenant uuid, pack jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_key text := install_field_pack.pack ->> 'key';
  v_version integer;
  v_entity text;
  v_fields jsonb;
  v_field jsonb;
  v_field_key text;
  v_label text;
  v_type text;
  v_required boolean;
  v_sensitive boolean;
  v_permission text;
  v_row record;
  v_id uuid;
  v_last text;
  v_rank text;
  v_created integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', install_field_pack.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if jsonb_typeof(install_field_pack.pack) is distinct from 'object' or install_field_pack.pack ->> 'apiVersion' is distinct from '1' then
    raise exception 'a field pack is an object with apiVersion 1' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  if v_key is null or v_key !~ '^[a-z][a-z0-9_.-]{0,62}$' then
    raise exception 'a field pack needs a key in lower case' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  begin
    v_version := (install_field_pack.pack ->> 'version')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    v_version := null;
  end;
  if v_version is null or v_version < 1 then
    raise exception 'a field pack needs a version of 1 or more' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  if jsonb_typeof(install_field_pack.pack -> 'subjects') is distinct from 'object' then
    raise exception 'a field pack needs subjects: { <type>: fields }' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;

  for v_entity, v_fields in select s.key, s.value from jsonb_each(install_field_pack.pack -> 'subjects') s order by s.key loop
    
    if jsonb_typeof(v_fields) is distinct from 'array' then
      raise exception 'the fields of a subject type are a list' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
    end if;
    for v_field in select f.value from jsonb_array_elements(v_fields) f loop
      if jsonb_typeof(v_field) is distinct from 'object' then
        raise exception 'a field is an object of key, label and type' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      v_field_key := v_field ->> 'key';
      v_label := v_field ->> 'label';
      v_type := v_field ->> 'type';
      v_permission := nullif(v_field ->> 'permission', '');
      if v_field_key is null or v_field_key !~ '^[a-z][a-z0-9_.-]{0,62}$' or v_label is null or btrim(v_label) = '' then
        raise exception 'a field needs a key in lower case and a label' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      if v_type is null or v_type not in ('text', 'number', 'date', 'bool', 'option', 'json', 'email', 'url', 'multi_option', 'user', 'rating', 'currency', 'bsn', 'iban', 'phone_e164') then
        raise exception 'a field needs one of the custom field types' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      if (v_field ? 'required' and jsonb_typeof(v_field -> 'required') <> 'boolean') or (v_field ? 'sensitive' and jsonb_typeof(v_field -> 'sensitive') <> 'boolean') then
        raise exception 'required and sensitive are booleans' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      v_required := coalesce((v_field ->> 'required')::boolean, false);
      v_sensitive := coalesce((v_field ->> 'sensitive')::boolean, false);

      select d."id" as id, d."pack" as pack, d."pack_version" as version, d."label" as label, d."type" as type,
        d."required" as required, d."sensitive" as sensitive, d."permission" as permission
      into v_row
      from "better_supabase"."field_definitions" d
      where d."org_id" = install_field_pack.tenant and d."entity" = v_entity and d."key" = v_field_key;

      if not found then
        select max(d."rank" collate "C") into v_last from "better_supabase"."field_definitions" d
        where d."org_id" = install_field_pack.tenant and d."entity" = v_entity;
        v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
        insert into "better_supabase"."field_definitions" ("org_id", "entity", "key", "label", "type", "required", "sensitive", "permission", "pack", "pack_version", "rank")
        values (install_field_pack.tenant, v_entity, v_field_key, v_label, v_type, v_required, v_sensitive, v_permission, v_key, v_version, v_rank)
        returning "id" into v_id;
        v_created := v_created + 1;
        null;
      elsif v_row.pack is distinct from v_key then
        raise exception 'the field already exists and doesn''t belong to this pack' using errcode = '23505', hint = 'FIELD_PACK_CONFLICT';
      elsif v_row.label = v_label and v_row.type = v_type and v_row.required = v_required and v_row.sensitive = v_sensitive
        and v_row.permission is not distinct from v_permission and v_row.version is not distinct from v_version then
        v_unchanged := v_unchanged + 1;
      else
        update "better_supabase"."field_definitions" set "label" = v_label, "type" = v_type, "required" = v_required, "sensitive" = v_sensitive,
          "permission" = v_permission, "pack_version" = v_version
        where "id" = v_row.id;
        v_updated := v_updated + 1;
        null;
      end if;
    end loop;
  end loop;
  return jsonb_build_object('pack', v_key, 'version', v_version, 'created', v_created, 'updated', v_updated, 'unchanged', v_unchanged);
end;
$$;
revoke execute on function "better_supabase"."install_field_pack"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."install_field_pack"(uuid, jsonb) to authenticated, service_role;

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
-- @bsb-hash sha256:2f372e03cc31a3775142510e905c3eac5585015d0adfc00b13e88d16eeb1e378
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('custom-fields', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
