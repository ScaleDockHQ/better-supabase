-- ==== schema supabase/schemas/900_better_supabase_061_custom_fields.sql
-- better-supabase module: custom-fields
-- @bsb-block custom-fields@4 managed
-- @bsb-hash sha256:07b98ac811e3d4ecf2438c9b680e98fbe73d553d50c546dfab3b1e699517ebed
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
  if to_regprocedure('better_supabase.member_workspace_ids(text[])') is null then
    create function better_supabase.member_workspace_ids(roles text[] default null)
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
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_insert on "better_supabase"."field_definitions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_update on "better_supabase"."field_definitions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_definitions";
create policy bsb_tenant_scope_delete on "better_supabase"."field_definitions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."field_values";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."field_values";
create policy bsb_tenant_scope_select on "better_supabase"."field_values" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."field_values";
create policy bsb_tenant_scope_insert on "better_supabase"."field_values" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."field_values";
create policy bsb_tenant_scope_update on "better_supabase"."field_values" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."field_values";
create policy bsb_tenant_scope_delete on "better_supabase"."field_values" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

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

-- ==== data supabase/better-supabase-data/900_better_supabase_061_custom_fields.sql
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
