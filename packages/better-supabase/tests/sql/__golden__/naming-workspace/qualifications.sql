-- ==== schema supabase/schemas/900_better_supabase_144_qualifications.sql
-- better-supabase module: qualifications
-- @bsb-block qualifications@1 managed
-- @bsb-hash sha256:9f1f51930c9d346a66f2fa9db615654151c14da731646b9e74dfa84a690b45bf
-- Qualification types and requirements, holdings for members, companies and assets, gaps by role, expiry and renewal notifications.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."qualification_types";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."qualification_types";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."qualification_types";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."qualification_types";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."qualification_types";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."qualification_requirements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."qualification_requirements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."qualification_requirements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."qualification_requirements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."qualification_requirements";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."qualifications";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."qualifications";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."qualifications";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."qualifications";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."qualifications";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Qualifications: types, requirements, holdings for members, companies and
-- assets, gaps, expiry and renewal.

create table if not exists "better_supabase"."qualification_types" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "name" text not null,
  "description" text,
  "holder_types" text[] not null default array['member']::text[],
  "valid_for_months" integer check ("valid_for_months" between 1 and 240),
  "evidence_required" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);
alter table "better_supabase"."qualification_types" enable row level security;
revoke all on "better_supabase"."qualification_types" from public, anon, authenticated;
grant select on "better_supabase"."qualification_types" to authenticated;
grant all on "better_supabase"."qualification_types" to service_role;
create policy qualification_types_read on better_supabase.qualification_types
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('qualifications.read')));

create table if not exists "better_supabase"."qualification_requirements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "type_id" uuid not null,
  "target_type" text not null check ("target_type" in ('role', 'team', 'job_title', 'asset_kind', 'segment', 'holder')),
  "target_value" text not null,
  "created_at" timestamptz not null default now(),
  unique ("type_id", "target_type", "target_value"),
  foreign key ("type_id") references "better_supabase"."qualification_types" ("id") on delete cascade
);
create index if not exists qualification_requirements_type_idx on "better_supabase"."qualification_requirements" ("type_id");
alter table "better_supabase"."qualification_requirements" enable row level security;
revoke all on "better_supabase"."qualification_requirements" from public, anon, authenticated;
grant select on "better_supabase"."qualification_requirements" to authenticated;
grant all on "better_supabase"."qualification_requirements" to service_role;
create policy qualification_requirements_read on better_supabase.qualification_requirements
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('qualifications.read')));

create table if not exists "better_supabase"."qualifications" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "type_id" uuid not null,
  "holder_type" text not null,
  "holder_id" text not null,
  "granted_on" date not null default current_date,
  "expires_on" date,
  "revoked_at" timestamptz,
  "revoke_reason" text,
  "evidence_note" text,
  "source" text not null default 'manual' check ("source" in ('manual', 'course', 'import')),
  "granted_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("type_id") references "better_supabase"."qualification_types" ("id") on delete restrict
);
create index if not exists qualifications_holder_idx on "better_supabase"."qualifications" ("tenant_id", "holder_type", "holder_id");
create index if not exists qualifications_expiry_idx on "better_supabase"."qualifications" ("type_id", "expires_on");
alter table "better_supabase"."qualifications" enable row level security;
revoke all on "better_supabase"."qualifications" from public, anon, authenticated;
grant select on "better_supabase"."qualifications" to authenticated;
grant all on "better_supabase"."qualifications" to service_role;
create policy qualifications_read on better_supabase.qualifications
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('qualifications.read')) or ("holder_type" = 'member' and "holder_id" = (select auth.uid())::text));

create or replace function "better_supabase"."save_qualification_type"(tenant uuid, key text, name text, holder_types text[] default array['member']::text[], valid_for_months integer default null, evidence_required boolean default false, description text default null, type_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."qualification_types"%rowtype;
  v_created boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', save_qualification_type.tenant, 'qualifications.manage'), false) then
    raise exception 'not allowed to manage qualification types' using errcode = '42501', hint = 'QUALIFICATION_FORBIDDEN';
  end if;
  if save_qualification_type.key !~ '^[a-z][a-z0-9_]{0,40}$' or cardinality(coalesce(save_qualification_type.holder_types, array['member']::text[])) = 0 then
    raise exception 'the key or holder types are invalid' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
  end if;
  if save_qualification_type.type_id is null then
    insert into "better_supabase"."qualification_types" ("tenant_id", "key", "name", "description", "holder_types", "valid_for_months", "evidence_required")
    values (save_qualification_type.tenant, save_qualification_type.key, trim(save_qualification_type.name), save_qualification_type.description, coalesce(save_qualification_type.holder_types, array['member']::text[]), save_qualification_type.valid_for_months, coalesce(save_qualification_type.evidence_required, false))
    on conflict ("tenant_id", "key") do update
      set "name" = excluded."name", "description" = excluded."description", "holder_types" = excluded."holder_types", "valid_for_months" = excluded."valid_for_months", "evidence_required" = excluded."evidence_required", "updated_at" = now()
    returning * into v_row;
    v_created := true;
  else
    update "better_supabase"."qualification_types" x set "key" = save_qualification_type.key, "name" = trim(save_qualification_type.name), "description" = save_qualification_type.description, "holder_types" = coalesce(save_qualification_type.holder_types, array['member']::text[]), "valid_for_months" = save_qualification_type.valid_for_months, "evidence_required" = coalesce(save_qualification_type.evidence_required, false), "updated_at" = now()
      where x."id" = save_qualification_type.type_id and x."tenant_id" = save_qualification_type.tenant
      returning * into v_row;
    if not found then
      raise exception 'qualification type not found' using errcode = 'P0002', hint = 'QUALIFICATION_TYPE_NOT_FOUND';
    end if;
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'holderTypes', v_row."holder_types", 'validForMonths', v_row."valid_for_months", 'evidenceRequired', v_row."evidence_required", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_qualification_type"(uuid, text, text, text[], integer, boolean, text, uuid) from public, anon;
grant execute on function "better_supabase"."save_qualification_type"(uuid, text, text, text[], integer, boolean, text, uuid) to authenticated, service_role;

create or replace function "better_supabase"."archive_qualification_type"(type_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."qualification_types"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."qualification_types" x where x."id" = archive_qualification_type.type_id;
  if not found then
    raise exception 'qualification type not found' using errcode = 'P0002', hint = 'QUALIFICATION_TYPE_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'qualifications.manage'), false) then
    raise exception 'not allowed to manage qualification types' using errcode = '42501', hint = 'QUALIFICATION_FORBIDDEN';
  end if;
  update "better_supabase"."qualification_types" x set "archived_at" = now(), "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'holderTypes', v_row."holder_types", 'validForMonths', v_row."valid_for_months", 'evidenceRequired', v_row."evidence_required", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_qualification_type"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_qualification_type"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_qualification_types"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'holderTypes', x."holder_types", 'validForMonths', x."valid_for_months", 'evidenceRequired', x."evidence_required", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."key"), '[]'::jsonb)
  from "better_supabase"."qualification_types" x
  where x."tenant_id" = $1 and x."tenant_id" in (select better_supabase.tenant_ids_with('qualifications.read'))
$$;
revoke execute on function "better_supabase"."list_qualification_types"(uuid) from public, anon;
grant execute on function "better_supabase"."list_qualification_types"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."add_qualification_requirement"(type_id uuid, target_type text, target_value text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type "better_supabase"."qualification_types"%rowtype;
  v_row "better_supabase"."qualification_requirements"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_type from "better_supabase"."qualification_types" x where x."id" = add_qualification_requirement.type_id;
  if not found then
    raise exception 'qualification type not found' using errcode = 'P0002', hint = 'QUALIFICATION_TYPE_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_type."tenant_id", 'qualifications.manage'), false) then
    raise exception 'not allowed to manage qualification requirements' using errcode = '42501', hint = 'QUALIFICATION_FORBIDDEN';
  end if;
  if add_qualification_requirement.target_type not in ('role', 'team', 'job_title', 'asset_kind', 'segment', 'holder') then
    raise exception 'the requirement target is invalid' using errcode = '22023', hint = 'QUALIFICATION_REQUIREMENT_INVALID';
  end if;
  insert into "better_supabase"."qualification_requirements" ("tenant_id", "type_id", "target_type", "target_value")
  values (v_type."tenant_id", v_type."id", add_qualification_requirement.target_type, add_qualification_requirement.target_value)
  on conflict ("type_id", "target_type", "target_value") do update set "target_value" = excluded."target_value"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'typeId', v_row."type_id", 'targetType', v_row."target_type", 'targetValue', v_row."target_value");
end;
$$;
revoke execute on function "better_supabase"."add_qualification_requirement"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."add_qualification_requirement"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."remove_qualification_requirement"(requirement_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."qualification_requirements"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."qualification_requirements" x where x."id" = remove_qualification_requirement.requirement_id;
  if not found then
    raise exception 'requirement not found' using errcode = 'P0002', hint = 'QUALIFICATION_REQUIREMENT_INVALID';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'qualifications.manage'), false) then
    raise exception 'not allowed to manage qualification requirements' using errcode = '42501', hint = 'QUALIFICATION_FORBIDDEN';
  end if;
  delete from "better_supabase"."qualification_requirements" x where x."id" = v_row."id";
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_qualification_requirement"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_qualification_requirement"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_qualification_requirements"(type_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'typeId', x."type_id", 'targetType', x."target_type", 'targetValue', x."target_value")), '[]'::jsonb)
  from "better_supabase"."qualification_requirements" x
  where x."type_id" = $1
$$;
revoke execute on function "better_supabase"."list_qualification_requirements"(uuid) from public, anon;
grant execute on function "better_supabase"."list_qualification_requirements"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."grant_qualification"(tenant uuid, type_key text, holder_type text, holder_id text, granted_on date default current_date, evidence_note text default null, source text default 'manual')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type "better_supabase"."qualification_types"%rowtype;
  v_row "better_supabase"."qualifications"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', grant_qualification.tenant, 'qualifications.grant'), false) then
    raise exception 'not allowed to grant qualifications' using errcode = '42501', hint = 'QUALIFICATION_FORBIDDEN';
  end if;
  select * into v_type from "better_supabase"."qualification_types" x where x."tenant_id" = grant_qualification.tenant and x."key" = grant_qualification.type_key;
  if not found or v_type."archived_at" is not null then
    raise exception 'qualification type not found or archived' using errcode = 'P0002', hint = 'QUALIFICATION_TYPE_NOT_FOUND';
  end if;
  if not grant_qualification.holder_type = any(v_type."holder_types") then
    raise exception 'the holder type is not allowed for this type' using errcode = '22023', hint = 'QUALIFICATION_HOLDER_INVALID';
  end if;
  if v_type."evidence_required" and nullif(trim(coalesce(grant_qualification.evidence_note, '')), '') is null then
    raise exception 'evidence is required' using errcode = '22023', hint = 'QUALIFICATION_EVIDENCE_REQUIRED';
  end if;
  insert into "better_supabase"."qualifications" ("tenant_id", "type_id", "holder_type", "holder_id", "granted_on", "expires_on", "evidence_note", "source")
  values (grant_qualification.tenant, v_type."id", grant_qualification.holder_type, grant_qualification.holder_id, coalesce(grant_qualification.granted_on, current_date), case when v_type."valid_for_months" is null then null else (coalesce(grant_qualification.granted_on, current_date) + make_interval(months => v_type."valid_for_months"))::date end, grant_qualification.evidence_note, coalesce(grant_qualification.source, 'manual'))
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'typeId', v_row."type_id", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'grantedOn', v_row."granted_on", 'expiresOn', v_row."expires_on", 'revokedAt', v_row."revoked_at", 'revokeReason', v_row."revoke_reason", 'evidenceNote', v_row."evidence_note", 'source', v_row."source", 'grantedBy', v_row."granted_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."grant_qualification"(uuid, text, text, text, date, text, text) from public, anon;
grant execute on function "better_supabase"."grant_qualification"(uuid, text, text, text, date, text, text) to authenticated, service_role;

create or replace function "better_supabase"."revoke_qualification"(qualification_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."qualifications"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."qualifications" x where x."id" = revoke_qualification.qualification_id;
  if not found then
    raise exception 'qualification not found' using errcode = 'P0002', hint = 'QUALIFICATION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'qualifications.manage'), false) then
    raise exception 'not allowed to revoke qualifications' using errcode = '42501', hint = 'QUALIFICATION_FORBIDDEN';
  end if;
  update "better_supabase"."qualifications" x set "revoked_at" = now(), "revoke_reason" = revoke_qualification.reason, "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'typeId', v_row."type_id", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'grantedOn', v_row."granted_on", 'expiresOn', v_row."expires_on", 'revokedAt', v_row."revoked_at", 'revokeReason', v_row."revoke_reason", 'evidenceNote', v_row."evidence_note", 'source', v_row."source", 'grantedBy', v_row."granted_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."revoke_qualification"(uuid, text) from public, anon;
grant execute on function "better_supabase"."revoke_qualification"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."qualifications_of"(holder_type text, holder_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'typeId', x."type_id", 'holderType', x."holder_type", 'holderId', x."holder_id", 'grantedOn', x."granted_on", 'expiresOn', x."expires_on", 'revokedAt', x."revoked_at", 'revokeReason', x."revoke_reason", 'evidenceNote', x."evidence_note", 'source', x."source", 'grantedBy', x."granted_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('status', case when x."revoked_at" is not null then 'revoked' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' when x."expires_on" is not null and x."expires_on" <= current_date + 30 then 'expiring' else 'valid' end) order by x."granted_on" desc), '[]'::jsonb)
  from "better_supabase"."qualifications" x
  where x."holder_type" = $1 and x."holder_id" = $2
    and x."tenant_id" in (select better_supabase.tenant_ids_with('qualifications.read'))
$$;
revoke execute on function "better_supabase"."qualifications_of"(text, text) from public, anon;
grant execute on function "better_supabase"."qualifications_of"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."qualification_gaps"(tenant uuid, holder_type text default 'member')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('holderType', m."user_id", 'holderId', m."user_id"::text, 'typeKey', ty."key", 'typeName', ty."name", 'status', case when q."id" is null then 'missing' when q."expires_on" < current_date then 'expired' else 'expiring' end, 'expiresOn', q."expires_on")), '[]'::jsonb)
  from "better_supabase"."memberships" m
  join "better_supabase"."qualification_requirements" rq on rq."tenant_id" = m."workspace_id" and rq."target_type" = 'role' and rq."target_value" = m."role"::text
  join "better_supabase"."qualification_types" ty on ty."id" = rq."type_id" and ty."archived_at" is null
  left join lateral (
    select x.* from "better_supabase"."qualifications" x
    where x."tenant_id" = m."workspace_id" and x."type_id" = ty."id" and x."holder_type" = 'member' and x."holder_id" = m."user_id"::text
      and x."revoked_at" is null and (x."expires_on" is null or x."expires_on" >= current_date)
    order by x."granted_on" desc limit 1
  ) q on true
  where m."workspace_id" = $1
    and (q."id" is null or q."expires_on" <= current_date + 30)
$$;
revoke execute on function "better_supabase"."qualification_gaps"(uuid, text) from public, anon;
grant execute on function "better_supabase"."qualification_gaps"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."notify_expiring_qualifications"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    select x.* from "better_supabase"."qualifications" x
    where x."revoked_at" is null and x."expires_on" is not null and x."expires_on" <= current_date + 30
  loop
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_expiring_qualifications"() from public, anon;
grant execute on function "better_supabase"."notify_expiring_qualifications"() to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."qualification_types";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."qualification_types";
create policy bsb_tenant_scope_select on "better_supabase"."qualification_types" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('qualifications.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."qualification_types";
create policy bsb_tenant_scope_insert on "better_supabase"."qualification_types" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."qualification_types";
create policy bsb_tenant_scope_update on "better_supabase"."qualification_types" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."qualification_types";
create policy bsb_tenant_scope_delete on "better_supabase"."qualification_types" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."qualification_requirements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."qualification_requirements";
create policy bsb_tenant_scope_select on "better_supabase"."qualification_requirements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('qualifications.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."qualification_requirements";
create policy bsb_tenant_scope_insert on "better_supabase"."qualification_requirements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."qualification_requirements";
create policy bsb_tenant_scope_update on "better_supabase"."qualification_requirements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."qualification_requirements";
create policy bsb_tenant_scope_delete on "better_supabase"."qualification_requirements" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."qualifications";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."qualifications";
create policy bsb_tenant_scope_select on "better_supabase"."qualifications" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('qualifications.read')) or ("holder_type" = 'member' and "holder_id" = (select auth.uid())::text))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."qualifications";
create policy bsb_tenant_scope_insert on "better_supabase"."qualifications" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."qualifications";
create policy bsb_tenant_scope_update on "better_supabase"."qualifications" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."qualifications";
create policy bsb_tenant_scope_delete on "better_supabase"."qualifications" as restrictive
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

-- ==== data supabase/better-supabase-data/900_better_supabase_144_qualifications.sql
-- better-supabase module: qualifications
-- @bsb-block-data qualifications
-- @bsb-hash sha256:1f1ceefd448a88336e3ab139e2cfc3cbc37f1aa636a3352e739a57f2a75c507c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('qualifications', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
