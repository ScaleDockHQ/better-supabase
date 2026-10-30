-- ==== schema supabase/schemas/900_better_supabase_143_qualifications.sql
-- better-supabase module: qualifications
-- @bsb-block qualifications@1 managed
-- @bsb-hash sha256:ea564ecd2e07248a6622a31fccf121e732e60416665ebe0fe3a0f66fb700870a
-- Qualification types (certifications, licences, skills) with a validity in months and optional evidence, requirements naming who must hold them (a role, a team, a job title, an asset kind, a segment or one holder), holdings of members, companies and assets that expire, a gap report, the holders qualified on a date, expiry notifications, and holdings granted from course certificates.
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
-- Qualifications: types of certification, licence or skill, who must hold
-- them (requirements), and the holdings of members, companies and assets
-- with their expiry.

create table if not exists "better_supabase"."qualification_types" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 4000),
  -- The holders the type applies to: member, company or asset.
  "holder_types" text[] not null check (cardinality("holder_types") > 0),
  -- A holding expires this many months after it is granted; null never expires.
  "valid_for_months" integer check ("valid_for_months" is null or "valid_for_months" between 1 and 240),
  "evidence_required" boolean not null default false,
  "course_id" uuid,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
create index if not exists "qualification_types_course_idx" on "better_supabase"."qualification_types" ("course_id") where "course_id" is not null;
alter table "better_supabase"."qualification_types" enable row level security;
revoke all on "better_supabase"."qualification_types" from public, anon, authenticated;
grant select on "better_supabase"."qualification_types" to authenticated;
grant all on "better_supabase"."qualification_types" to service_role;
drop policy if exists qualification_types_read on "better_supabase"."qualification_types";
create policy qualification_types_read on "better_supabase"."qualification_types"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('qualifications.read')) or "tenant_id" in (select better_supabase.member_organization_ids()));

create table if not exists "better_supabase"."qualification_requirements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "type_id" uuid not null,
  -- Who must hold the type: a role, a team, a job title, an asset kind, a
  -- segment of companies, or one holder.
  "target_type" text not null check ("target_type" in ('role', 'team', 'job_title', 'asset_kind', 'segment', 'holder')),
  "target_value" text not null check (length("target_value") between 1 and 200),
  "created_at" timestamptz not null default now(),
  unique ("type_id", "target_type", "target_value"),
  foreign key ("tenant_id", "type_id") references "better_supabase"."qualification_types" ("tenant_id", "id") on delete cascade
);
create index if not exists "qualification_requirements_tenant_idx" on "better_supabase"."qualification_requirements" ("tenant_id", "type_id");
alter table "better_supabase"."qualification_requirements" enable row level security;
revoke all on "better_supabase"."qualification_requirements" from public, anon, authenticated;
grant select on "better_supabase"."qualification_requirements" to authenticated;
grant all on "better_supabase"."qualification_requirements" to service_role;
drop policy if exists qualification_requirements_read on "better_supabase"."qualification_requirements";
create policy qualification_requirements_read on "better_supabase"."qualification_requirements"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('qualifications.read')) or "tenant_id" in (select better_supabase.member_organization_ids()));

create table if not exists "better_supabase"."qualifications" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "type_id" uuid not null,
  "holder_type" text not null check ("holder_type" in ('member', 'company', 'asset')),
  "holder_id" text not null check (length("holder_id") between 1 and 200),
  "granted_on" date not null,
  "expires_on" date,
  "revoked_at" timestamptz,
  "revoke_reason" text check ("revoke_reason" is null or length("revoke_reason") <= 2000),
  "evidence_attachment_id" uuid,
  "evidence_note" text check ("evidence_note" is null or length("evidence_note") <= 4000),
  "source" text not null default 'manual' check ("source" in ('manual', 'course', 'import')),
  -- The record behind a course or import holding, such as the certificate id.
  "source_id" text,
  "granted_by" uuid,
  -- The status notify_expiring_qualifications last reported, so each one
  -- notifies once.
  "notified_status" text check ("notified_status" is null or "notified_status" in ('expiring', 'expired')),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("expires_on" is null or "expires_on" >= "granted_on"),
  foreign key ("tenant_id", "type_id") references "better_supabase"."qualification_types" ("tenant_id", "id") on delete cascade
);
alter table "better_supabase"."qualifications" add column if not exists "app_note" text;
create index if not exists "qualifications_holder_idx" on "better_supabase"."qualifications" ("tenant_id", "holder_type", "holder_id");
create index if not exists "qualifications_type_idx" on "better_supabase"."qualifications" ("tenant_id", "type_id");
create index if not exists "qualifications_expiry_idx" on "better_supabase"."qualifications" ("type_id", "expires_on");
create index if not exists "qualifications_source_idx" on "better_supabase"."qualifications" ("source", "source_id") where "source_id" is not null;
alter table "better_supabase"."qualifications" enable row level security;
revoke all on "better_supabase"."qualifications" from public, anon, authenticated;
grant select on "better_supabase"."qualifications" to authenticated;
grant all on "better_supabase"."qualifications" to service_role;
drop policy if exists qualifications_read on "better_supabase"."qualifications";
create policy qualifications_read on "better_supabase"."qualifications"
  for select to authenticated
  using (("holder_type" = 'member' and "holder_id" = (select auth.uid())::text) or "tenant_id" in (select better_supabase.tenant_ids_with('qualifications.read')));

-- Creates a qualification type, or changes one (type_id). Without type_id,
-- a type with the same key is updated (and unarchived). valid_for_months
-- sets how long a holding lasts (null: it never expires); course_id grants
-- the type when a member earns that course's certificate.
create or replace function "better_supabase"."save_qualification_type"(tenant uuid, key text, name text, holder_types text[], valid_for_months integer default null, evidence_required boolean default false, course_id uuid default null, description text default null, type_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."qualification_types"%rowtype;
  v_new boolean;
  v_name text := nullif(trim(save_qualification_type.name), '');
  v_holders text[] := array(select distinct h from unnest(save_qualification_type.holder_types) h where h is not null order by h);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_qualification_type.tenant, 'qualifications.manage'), false)) then
    raise exception 'not allowed to manage qualifications' using errcode = '42501', hint = 'QUALIFICATION_FORBIDDEN';
  end if;
  if save_qualification_type.key is null or save_qualification_type.key !~ '^[a-z0-9][a-z0-9_.-]{0,62}$' then
    raise exception 'the key takes lowercase letters, digits, dots, dashes and underscores' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a qualification type needs a name of at most 200 characters' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
  end if;
  if cardinality(v_holders) = 0 or not (v_holders <@ array['member', 'company', 'asset']::text[]) then
    raise exception 'holder_types takes member, company, asset' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
  end if;
  if 'company' = any(v_holders) then
    raise exception 'company holders need the contacts block' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
  end if;
  if 'asset' = any(v_holders) then
    raise exception 'asset holders need the assets block' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
  end if;
  if save_qualification_type.valid_for_months is not null and save_qualification_type.valid_for_months not between 1 and 240 then
    raise exception 'valid_for_months is between 1 and 240' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
  end if;
  if save_qualification_type.course_id is not null then
    raise exception 'course_id needs the courses block' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_qualification_type_save"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using save_qualification_type.tenant, save_qualification_type.key;
    end if;
  end;
  if save_qualification_type.type_id is null then
    v_new := not exists (select 1 from "better_supabase"."qualification_types" x where x."tenant_id" = save_qualification_type.tenant and x."key" = save_qualification_type.key);
    insert into "better_supabase"."qualification_types" ("tenant_id", "key", "name", "description", "holder_types", "valid_for_months", "evidence_required", "course_id")
    values (save_qualification_type.tenant, save_qualification_type.key, v_name, nullif(trim(save_qualification_type.description), ''), v_holders, save_qualification_type.valid_for_months, coalesce(save_qualification_type.evidence_required, false), save_qualification_type.course_id)
    on conflict ("tenant_id", "key") do update set
      "name" = v_name,
      "description" = nullif(trim(save_qualification_type.description), ''),
      "holder_types" = v_holders,
      "valid_for_months" = save_qualification_type.valid_for_months,
      "evidence_required" = coalesce(save_qualification_type.evidence_required, false),
      "course_id" = save_qualification_type.course_id,
      "archived_at" = null,
      "updated_at" = now()
    returning * into v_row;
  else
    v_new := false;
    update "better_supabase"."qualification_types" x set
      "key" = save_qualification_type.key,
      "name" = v_name,
      "description" = nullif(trim(save_qualification_type.description), ''),
      "holder_types" = v_holders,
      "valid_for_months" = save_qualification_type.valid_for_months,
      "evidence_required" = coalesce(save_qualification_type.evidence_required, false),
      "course_id" = save_qualification_type.course_id,
      "archived_at" = null,
      "updated_at" = now()
    where x."id" = save_qualification_type.type_id and x."tenant_id" = save_qualification_type.tenant
    returning x.* into v_row;
    if not found then
      raise exception 'qualification type not found' using errcode = 'P0002', hint = 'QUALIFICATION_TYPE_NOT_FOUND';
    end if;
  end if;
  if v_new then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_qualification_type_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'holderTypes', to_jsonb(v_row."holder_types"), 'validForMonths', v_row."valid_for_months", 'evidenceRequired', v_row."evidence_required", 'courseId', v_row."course_id", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_qualification_type"(uuid, text, text, text[], integer, boolean, uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."save_qualification_type"(uuid, text, text, text[], integer, boolean, uuid, text, uuid) to authenticated, service_role;

-- Archives a type: it takes no new holdings and leaves the gap report, and
-- its holdings stay.
create or replace function "better_supabase"."archive_qualification_type"(type_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'qualifications.manage'), false)) then
    raise exception 'not allowed to manage qualifications' using errcode = '42501', hint = 'QUALIFICATION_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    update "better_supabase"."qualification_types" x set "archived_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'holderTypes', to_jsonb(v_row."holder_types"), 'validForMonths', v_row."valid_for_months", 'evidenceRequired', v_row."evidence_required", 'courseId', v_row."course_id", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_qualification_type"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_qualification_type"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_qualification_types"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'holderTypes', to_jsonb(x."holder_types"), 'validForMonths', x."valid_for_months", 'evidenceRequired', x."evidence_required", 'courseId', x."course_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."key"), '[]'::jsonb)
  from "better_supabase"."qualification_types" x
  where x."tenant_id" = list_qualification_types.tenant
    and (coalesce(list_qualification_types.include_archived, false) or x."archived_at" is null)
$$;
revoke execute on function "better_supabase"."list_qualification_types"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_qualification_types"(uuid, boolean) to authenticated, service_role;

-- Says who must hold a type: target_type role (a membership role), team (a
-- team id), job_title (an employee job title, any case), asset_kind (an
-- asset kind), segment (a segment of companies) or holder (one holder id).
create or replace function "better_supabase"."add_qualification_requirement"(type_id uuid, target_type text, target_value text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_type "better_supabase"."qualification_types"%rowtype;
  v_row "better_supabase"."qualification_requirements"%rowtype;
  v_value text := nullif(trim(add_qualification_requirement.target_value), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_type from "better_supabase"."qualification_types" x where x."id" = add_qualification_requirement.type_id;
  if not found then
    raise exception 'qualification type not found' using errcode = 'P0002', hint = 'QUALIFICATION_TYPE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_type."tenant_id", 'qualifications.manage'), false)) then
    raise exception 'not allowed to manage qualifications' using errcode = '42501', hint = 'QUALIFICATION_FORBIDDEN';
  end if;
  if add_qualification_requirement.target_type is null or add_qualification_requirement.target_type not in ('role', 'team', 'job_title', 'asset_kind', 'segment', 'holder') then
    raise exception 'target_type is one of role, team, job_title, asset_kind, segment, holder' using errcode = '22023', hint = 'QUALIFICATION_REQUIREMENT_INVALID';
  end if;
  if v_value is null or length(v_value) > 200 then
    raise exception 'a requirement needs a target value of at most 200 characters' using errcode = '22023', hint = 'QUALIFICATION_REQUIREMENT_INVALID';
  end if;
  if add_qualification_requirement.target_type = 'role' then
    if not ('member' = any(v_type."holder_types")) then
      raise exception 'role requirements apply to member holders' using errcode = '22023', hint = 'QUALIFICATION_REQUIREMENT_INVALID';
    end if;
  end if;
  if add_qualification_requirement.target_type = 'team' then
    raise exception 'team requirements need the teams block' using errcode = '22023', hint = 'QUALIFICATION_REQUIREMENT_INVALID';
    if not ('member' = any(v_type."holder_types")) then
      raise exception 'team requirements apply to member holders' using errcode = '22023', hint = 'QUALIFICATION_REQUIREMENT_INVALID';
    end if;
  end if;
  if add_qualification_requirement.target_type = 'job_title' then
    raise exception 'job_title requirements need the employees block' using errcode = '22023', hint = 'QUALIFICATION_REQUIREMENT_INVALID';
    if not ('member' = any(v_type."holder_types")) then
      raise exception 'job_title requirements apply to member holders' using errcode = '22023', hint = 'QUALIFICATION_REQUIREMENT_INVALID';
    end if;
  end if;
  if add_qualification_requirement.target_type = 'asset_kind' then
    raise exception 'asset_kind requirements need the assets block' using errcode = '22023', hint = 'QUALIFICATION_REQUIREMENT_INVALID';
    if not ('asset' = any(v_type."holder_types")) then
      raise exception 'asset_kind requirements apply to asset holders' using errcode = '22023', hint = 'QUALIFICATION_REQUIREMENT_INVALID';
    end if;
  end if;
  if add_qualification_requirement.target_type = 'segment' then
    raise exception 'segment requirements need the segments block' using errcode = '22023', hint = 'QUALIFICATION_REQUIREMENT_INVALID';
    if not ('company' = any(v_type."holder_types")) then
      raise exception 'segment requirements apply to company holders' using errcode = '22023', hint = 'QUALIFICATION_REQUIREMENT_INVALID';
    end if;
  end if;
  insert into "better_supabase"."qualification_requirements" ("tenant_id", "type_id", "target_type", "target_value")
  values (v_type."tenant_id", v_type."id", add_qualification_requirement.target_type, v_value)
  on conflict ("type_id", "target_type", "target_value") do nothing;
  select * into v_row from "better_supabase"."qualification_requirements" x
  where x."type_id" = v_type."id" and x."target_type" = add_qualification_requirement.target_type and x."target_value" = v_value;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'qualificationTypeId', v_row."type_id", 'targetType', v_row."target_type", 'targetValue', v_row."target_value", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."add_qualification_requirement"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."add_qualification_requirement"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."remove_qualification_requirement"(requirement_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."qualification_requirements"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."qualification_requirements" x where x."id" = remove_qualification_requirement.requirement_id;
  if not found then
    raise exception 'requirement not found' using errcode = 'P0002', hint = 'QUALIFICATION_REQUIREMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'qualifications.manage'), false)) then
    raise exception 'not allowed to manage qualifications' using errcode = '42501', hint = 'QUALIFICATION_FORBIDDEN';
  end if;
  delete from "better_supabase"."qualification_requirements" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'qualificationTypeId', v_row."type_id", 'targetType', v_row."target_type", 'targetValue', v_row."target_value", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."remove_qualification_requirement"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_qualification_requirement"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_qualification_requirements"(type_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'qualificationTypeId', x."type_id", 'targetType', x."target_type", 'targetValue', x."target_value", 'createdAt', x."created_at") order by x."target_type", x."target_value"), '[]'::jsonb)
  from "better_supabase"."qualification_requirements" x
  where x."type_id" = list_qualification_requirements.type_id
$$;
revoke execute on function "better_supabase"."list_qualification_requirements"(uuid) from public, anon;
grant execute on function "better_supabase"."list_qualification_requirements"(uuid) to authenticated, service_role;

-- Grants a qualification to a holder (a member's user id, a company id or
-- an asset id). The holding expires valid_for_months after granted_on;
-- earlier holdings of the same type stay as history.
drop function if exists "better_supabase"."grant_qualification"(uuid, text, text, text, date, uuid, text);
create or replace function "better_supabase"."grant_qualification"(tenant uuid, type_key text, holder_type text, holder_id text, granted_on date default current_date, evidence_attachment_id uuid default null, evidence_note text default null, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_type "better_supabase"."qualification_types"%rowtype;
  v_row "better_supabase"."qualifications"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', grant_qualification.tenant, 'qualifications.grant'), false)) then
    raise exception 'not allowed to grant qualifications' using errcode = '42501', hint = 'QUALIFICATION_FORBIDDEN';
  end if;
  select * into v_type from "better_supabase"."qualification_types" x
  where x."tenant_id" = grant_qualification.tenant and x."key" = grant_qualification.type_key and x."archived_at" is null;
  if not found then
    raise exception 'qualification type not found' using errcode = 'P0002', hint = 'QUALIFICATION_TYPE_NOT_FOUND';
  end if;
  if grant_qualification.holder_type is null or not (grant_qualification.holder_type = any(v_type."holder_types")) then
    raise exception 'the type doesn''t apply to this holder type' using errcode = '22023', hint = 'QUALIFICATION_HOLDER_INVALID';
  end if;
  if grant_qualification.holder_id is null or not (case grant_qualification.holder_type
      when 'member' then exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = v_type."tenant_id" and m."user_id"::text = grant_qualification.holder_id and m."disabled_at" is null)
      else false
    end) then
    raise exception 'the holder isn''t in this organization' using errcode = '22023', hint = 'QUALIFICATION_HOLDER_INVALID';
  end if;
  if grant_qualification.granted_on is null then
    raise exception 'granted_on is required' using errcode = '22023', hint = 'QUALIFICATION_INVALID';
  end if;
  if v_type."evidence_required" and grant_qualification.evidence_attachment_id is null and nullif(trim(grant_qualification.evidence_note), '') is null then
    raise exception 'this qualification type needs evidence' using errcode = '22023', hint = 'QUALIFICATION_EVIDENCE_REQUIRED';
  end if;
  if grant_qualification.evidence_attachment_id is not null then
    raise exception 'evidence files need the attachments block' using errcode = '22023', hint = 'QUALIFICATION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_qualification_grant"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using v_type."id", grant_qualification.holder_type, grant_qualification.holder_id;
    end if;
  end;
  insert into "better_supabase"."qualifications" ("tenant_id", "type_id", "holder_type", "holder_id", "granted_on", "expires_on", "evidence_attachment_id", "evidence_note", "source", "granted_by")
  values (v_type."tenant_id", v_type."id", grant_qualification.holder_type, grant_qualification.holder_id, grant_qualification.granted_on, case when v_type."valid_for_months" is null then null else (grant_qualification.granted_on + make_interval(months => v_type."valid_for_months"))::date end, grant_qualification.evidence_attachment_id, nullif(trim(grant_qualification.evidence_note), ''), 'manual', (select auth.uid()))
  returning * into v_row;
  update "better_supabase"."qualifications" x set "app_note" = case when grant_qualification.fields ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."qualifications", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(grant_qualification.fields) e where e.key in ('app_note'))) r
  where x."id" = v_row."id"
  returning x.* into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_qualification_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'qualificationTypeId', v_row."type_id", 'typeKey', v_type."key", 'typeName', v_type."name", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'grantedOn', v_row."granted_on", 'expiresOn', v_row."expires_on", 'revokedAt', v_row."revoked_at", 'revokeReason', v_row."revoke_reason", 'evidenceAttachmentId', v_row."evidence_attachment_id", 'evidenceNote', v_row."evidence_note", 'source', v_row."source", 'sourceId', v_row."source_id", 'grantedBy', v_row."granted_by", 'status', case
    when v_row."revoked_at" is not null then 'revoked'
    when v_row."expires_on" is not null and v_row."expires_on" < current_date then 'expired'
    when v_row."expires_on" is not null and v_row."expires_on" <= current_date + 30 then 'expiring'
    else 'valid'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."grant_qualification"(uuid, text, text, text, date, uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."grant_qualification"(uuid, text, text, text, date, uuid, text, jsonb) to authenticated, service_role;

-- Revokes a holding. Revoking one already revoked changes nothing.
create or replace function "better_supabase"."revoke_qualification"(qualification_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."qualifications"%rowtype;
  v_type "better_supabase"."qualification_types"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."qualifications" x where x."id" = revoke_qualification.qualification_id;
  if not found then
    raise exception 'qualification not found' using errcode = 'P0002', hint = 'QUALIFICATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'qualifications.grant'), false)) then
    raise exception 'not allowed to revoke qualifications' using errcode = '42501', hint = 'QUALIFICATION_FORBIDDEN';
  end if;
  select * into v_type from "better_supabase"."qualification_types" x where x."id" = v_row."type_id";
  if v_row."revoked_at" is null then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_qualification_revoke"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
    update "better_supabase"."qualifications" x set "revoked_at" = now(), "revoke_reason" = left(nullif(trim(revoke_qualification.reason), ''), 2000), "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_qualification_revoke"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'qualificationTypeId', v_row."type_id", 'typeKey', v_type."key", 'typeName', v_type."name", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'grantedOn', v_row."granted_on", 'expiresOn', v_row."expires_on", 'revokedAt', v_row."revoked_at", 'revokeReason', v_row."revoke_reason", 'evidenceAttachmentId', v_row."evidence_attachment_id", 'evidenceNote', v_row."evidence_note", 'source', v_row."source", 'sourceId', v_row."source_id", 'grantedBy', v_row."granted_by", 'status', case
    when v_row."revoked_at" is not null then 'revoked'
    when v_row."expires_on" is not null and v_row."expires_on" < current_date then 'expired'
    when v_row."expires_on" is not null and v_row."expires_on" <= current_date + 30 then 'expiring'
    else 'valid'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."revoke_qualification"(uuid, text) from public, anon;
grant execute on function "better_supabase"."revoke_qualification"(uuid, text) to authenticated, service_role;

-- The holdings of one holder the caller may read, newest first, with each
-- one's status: valid, expiring, expired or revoked.
create or replace function "better_supabase"."qualifications_of"(holder_type text, holder_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'qualificationTypeId', x."type_id", 'typeKey', y."key", 'typeName', y."name", 'holderType', x."holder_type", 'holderId', x."holder_id", 'grantedOn', x."granted_on", 'expiresOn', x."expires_on", 'revokedAt', x."revoked_at", 'revokeReason', x."revoke_reason", 'evidenceAttachmentId', x."evidence_attachment_id", 'evidenceNote', x."evidence_note", 'source', x."source", 'sourceId', x."source_id", 'grantedBy', x."granted_by", 'status', case
    when x."revoked_at" is not null then 'revoked'
    when x."expires_on" is not null and x."expires_on" < current_date then 'expired'
    when x."expires_on" is not null and x."expires_on" <= current_date + 30 then 'expiring'
    else 'valid'
  end, 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'fields', jsonb_build_object('app_note', x."app_note")) order by x."granted_on" desc, y."name"), '[]'::jsonb)
  from "better_supabase"."qualifications" x
  join "better_supabase"."qualification_types" y on y."id" = x."type_id"
  where x."holder_type" = qualifications_of.holder_type and x."holder_id" = qualifications_of.holder_id
$$;
revoke execute on function "better_supabase"."qualifications_of"(text, text) from public, anon;
grant execute on function "better_supabase"."qualifications_of"(text, text) to authenticated, service_role;

-- The gaps of one holder type: each (holder, type) a requirement asks for
-- and the holder doesn't hold validly, as missing, expired or expiring.
-- filters takes typeKey, teamId (members of a team), status and holderId.
-- Members may read their own gaps (holderId is their user id).
create or replace function "better_supabase"."qualification_gaps"(tenant uuid, holder_type text default 'member', filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_filters jsonb := coalesce(qualification_gaps.filters, '{}'::jsonb);
  v_holder text := nullif(v_filters ->> 'holderId', '');
  v_team text := nullif(v_filters ->> 'teamId', '');
  v_type_key text := nullif(v_filters ->> 'typeKey', '');
  v_status text := nullif(v_filters ->> 'status', '');
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', qualification_gaps.tenant, 'qualifications.read'), false)
    or (qualification_gaps.holder_type = 'member' and v_holder is not null and v_holder = (select auth.uid())::text and exists (select 1 from "better_supabase"."memberships" mm where mm."organization_id" = qualification_gaps.tenant and mm."user_id" = (select auth.uid()) and mm."disabled_at" is null))) then
    raise exception 'not allowed to read qualifications' using errcode = '42501', hint = 'QUALIFICATION_FORBIDDEN';
  end if;
  if v_status is not null and v_status not in ('missing', 'expired', 'expiring') then
    raise exception 'status is missing, expired or expiring' using errcode = '22023', hint = 'QUALIFICATION_INVALID';
  end if;
  if v_team is not null then
    raise exception 'the teamId filter needs the teams block' using errcode = '22023', hint = 'QUALIFICATION_INVALID';
  end if;
  with holders as (
      select h.id, coalesce((select u.email::text from auth.users u where u.id::text = h.id), h.id) as title from (select ms."user_id"::text as id from "better_supabase"."memberships" ms where ms."organization_id" = qualification_gaps.tenant and ms."disabled_at" is null) h where qualification_gaps.holder_type = 'member'
  ), required as (
    select distinct h.id as holder_id, h.title, y."id" as type_id, y."key" as type_key, y."name" as type_name
    from holders h
    join "better_supabase"."qualification_types" y on y."tenant_id" = qualification_gaps.tenant and y."archived_at" is null and qualification_gaps.holder_type = any(y."holder_types")
      and (v_type_key is null or y."key" = v_type_key)
    join "better_supabase"."qualification_requirements" rq on rq."type_id" = y."id"
    where (v_holder is null or h.id = v_holder)
      and case rq."target_type"::text
        when 'holder' then rq."target_value" = h.id
        when 'role' then qualification_gaps.holder_type = 'member' and exists (select 1 from "better_supabase"."memberships" m2 where m2."organization_id" = qualification_gaps.tenant and m2."user_id"::text = h.id and m2."role"::text = rq."target_value" and m2."disabled_at" is null)
        else false
      end
  ), rated as (
    select rq.*, s.valid_until from required rq
    left join lateral (
      select max(coalesce(x."expires_on", 'infinity'::date)) as valid_until
      from "better_supabase"."qualifications" x
      where x."type_id" = rq.type_id and x."holder_type" = qualification_gaps.holder_type and x."holder_id" = rq.holder_id
        and x."revoked_at" is null and x."granted_on" <= current_date
    ) s on true
  ), gaps as (
    select rt.*, case
      when rt.valid_until is null then 'missing'
      when rt.valid_until < current_date then 'expired'
      when rt.valid_until <= current_date + 30 then 'expiring'
    end as status
    from rated rt
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'holderType', qualification_gaps.holder_type,
    'holderId', g.holder_id,
    'holderTitle', g.title,
    'typeKey', g.type_key,
    'typeName', g.type_name,
    'status', g.status,
    'expiresOn', case when g.status = 'missing' then null else g.valid_until end
  ) order by g.title, g.holder_id, g.type_name), '[]'::jsonb)
  into v_result
  from gaps g
  where g.status is not null and (v_status is null or g.status = v_status);
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."qualification_gaps"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."qualification_gaps"(uuid, text, jsonb) to authenticated, service_role;

-- The ids of the holders of one type that hold it validly on on_date, for
-- shift planning and party roles. Members of the organization may call it.
create or replace function "better_supabase"."qualified_holders"(tenant uuid, type_key text, holder_type text default 'member', on_date date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_on date := coalesce(qualified_holders.on_date, current_date);
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', qualified_holders.tenant, 'qualifications.read'), false) or exists (select 1 from "better_supabase"."memberships" mm where mm."organization_id" = qualified_holders.tenant and mm."user_id" = (select auth.uid()) and mm."disabled_at" is null)) then
    raise exception 'not allowed to read qualifications' using errcode = '42501', hint = 'QUALIFICATION_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(distinct x."holder_id" order by x."holder_id"), '[]'::jsonb)
  into v_result
  from "better_supabase"."qualifications" x
  join "better_supabase"."qualification_types" y on y."id" = x."type_id"
  where y."tenant_id" = qualified_holders.tenant and y."key" = qualified_holders.type_key
    and x."holder_type" = qualified_holders.holder_type
    and x."granted_on" <= v_on
    and (x."expires_on" is null or x."expires_on" >= v_on)
    and (x."revoked_at" is null or x."revoked_at"::date > v_on)
    and case x."holder_type"
      when 'member' then exists (select 1 from "better_supabase"."memberships" mh where mh."organization_id" = qualified_holders.tenant and mh."user_id"::text = x."holder_id" and mh."disabled_at" is null)
      else false
    end;
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."qualified_holders"(uuid, text, text, date) from public, anon;
grant execute on function "better_supabase"."qualified_holders"(uuid, text, text, date) to authenticated, service_role;

-- Reports each holding that entered the renewal window (30 days) or
-- expired without a newer holding of the type, once per holding and status.
-- Returns how many it reported. Run it daily from a job.
create or replace function "better_supabase"."notify_expiring_qualifications"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."qualifications"%rowtype;
  v_type "better_supabase"."qualification_types"%rowtype;
  v_status text;
  v_count integer := 0;
begin
  for v_row in
    select x.* from "better_supabase"."qualifications" x
    where x."revoked_at" is null and x."expires_on" is not null
      and x."expires_on" <= current_date + 30
      and x."notified_status" is distinct from (case when x."expires_on" < current_date then 'expired' else 'expiring' end)
      and not exists (
        select 1 from "better_supabase"."qualifications" n
        where n."type_id" = x."type_id" and n."holder_type" = x."holder_type" and n."holder_id" = x."holder_id"
          and n."id" <> x."id" and n."revoked_at" is null
          and (n."expires_on" is null or n."expires_on" > x."expires_on")
      )
    order by x."expires_on"
    for update of x skip locked
  loop
    v_status := case when v_row."expires_on" < current_date then 'expired' else 'expiring' end;
    select * into v_type from "better_supabase"."qualification_types" y where y."id" = v_row."type_id";
    if v_status = 'expired' then
      null;
    else
      null;
    end if;
    update "better_supabase"."qualifications" x set "notified_status" = v_status where x."id" = v_row."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_expiring_qualifications"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_expiring_qualifications"() to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."qualification_types";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."qualification_types";
create policy bsb_tenant_scope_select on "better_supabase"."qualification_types" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('qualifications.read')) or "tenant_id" in (select better_supabase.member_organization_ids()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."qualification_types";
create policy bsb_tenant_scope_insert on "better_supabase"."qualification_types" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."qualification_types";
create policy bsb_tenant_scope_update on "better_supabase"."qualification_types" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."qualification_types";
create policy bsb_tenant_scope_delete on "better_supabase"."qualification_types" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."qualification_requirements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."qualification_requirements";
create policy bsb_tenant_scope_select on "better_supabase"."qualification_requirements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('qualifications.read')) or "tenant_id" in (select better_supabase.member_organization_ids()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."qualification_requirements";
create policy bsb_tenant_scope_insert on "better_supabase"."qualification_requirements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."qualification_requirements";
create policy bsb_tenant_scope_update on "better_supabase"."qualification_requirements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."qualification_requirements";
create policy bsb_tenant_scope_delete on "better_supabase"."qualification_requirements" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."qualifications";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."qualifications";
create policy bsb_tenant_scope_select on "better_supabase"."qualifications" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("holder_type" = 'member' and "holder_id" = (select auth.uid())::text) or "tenant_id" in (select better_supabase.tenant_ids_with('qualifications.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."qualifications";
create policy bsb_tenant_scope_insert on "better_supabase"."qualifications" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."qualifications";
create policy bsb_tenant_scope_update on "better_supabase"."qualifications" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."qualifications";
create policy bsb_tenant_scope_delete on "better_supabase"."qualifications" as restrictive
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

-- ==== data supabase/better-supabase-data/900_better_supabase_143_qualifications.sql
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
