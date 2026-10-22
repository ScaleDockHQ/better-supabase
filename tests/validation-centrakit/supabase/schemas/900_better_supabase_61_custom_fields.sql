-- better-supabase module: custom-fields
-- @bsb-block custom-fields@3 adopt
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
alter table "centrakit"."field_definitions" add column if not exists "encrypted" boolean not null default false;

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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_field_definition.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  insert into "centrakit"."field_definitions" ("tenant_id", "entity", "key", "label", "type", "sensitive")
  values (save_field_definition.tenant, save_field_definition.entity, save_field_definition.key, save_field_definition.label, save_field_definition.type, coalesce(save_field_definition.sensitive, false))
  on conflict ("tenant_id", "entity", "key")
  do update set "label" = excluded."label", "sensitive" = excluded."sensitive"
  returning "id" into v_id;
  perform "better_supabase".emit_event('custom_field.saved', jsonb_build_object('organizationId', save_field_definition.tenant, 'id', v_id, 'entity', save_field_definition.entity), 'custom-fields/' || coalesce(v_id::text, save_field_definition.key), (save_field_definition.tenant)::text, null, 'domain');
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
  from "centrakit"."field_values" v
  left join "centrakit"."field_definitions" d on d."id" = v."definition_id"
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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_field_value.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to set custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  insert into "centrakit"."field_values" ("tenant_id", "definition_id", "subject_type", "subject_id", "value_text")
  values (set_field_value.tenant, set_field_value.definition, set_field_value.subject_type, set_field_value.subject_id, set_field_value.value)
  returning "id" into v_id;
  perform "better_supabase".emit_event('field_value.set', jsonb_build_object('organizationId', set_field_value.tenant, 'id', v_id, 'subjectType', set_field_value.subject_type, 'subjectId', set_field_value.subject_id), 'field-values/' || v_id::text, (set_field_value.tenant)::text, null, 'domain');
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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "centrakit"."field_definitions" where "id" = delete_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  delete from "centrakit"."field_definitions" where "id" = delete_field_definition.definition;
  perform "better_supabase".emit_event('custom_field.deleted', jsonb_build_object('organizationId', v_tenant, 'id', delete_field_definition.definition), 'custom-fields/' || delete_field_definition.definition::text, (v_tenant)::text, null, 'domain');
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
    'rank', null
  ) order by d."key"), '[]'::jsonb)
  from "centrakit"."field_definitions" d
  where d."tenant_id" = list_field_definitions.tenant
    and d."entity" = list_field_definitions.entity
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_field_definitions.tenant, 'custom_fields.read'), false))
$$;
revoke execute on function "better_supabase"."list_field_definitions"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_field_definitions"(uuid, text) to authenticated, service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;
