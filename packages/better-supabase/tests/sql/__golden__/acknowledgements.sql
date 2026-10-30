-- ==== alone: schema supabase/schemas/900_better_supabase_147_acknowledgements.sql
-- better-supabase module: acknowledgements
-- @bsb-block acknowledgements@1 managed
-- @bsb-hash sha256:fbeb41014bf4ffcb7abc493e4526bdec29ba9790ed1aec153f36346c1118e553
-- Members confirm they read the current version of a record: assignments to a member, a team or a role, a due date per assignment, a click or a completed signature, and a reminder once a version is overdue.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgement_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgements";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgement_notices";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Acknowledgements: members confirm they read the current version of a
-- record they are assigned to, directly, through a team or through a role.

-- Who has to acknowledge a record: a member, everyone in a team, or everyone
-- holding a role, with an optional number of days to do it in.
create table if not exists "better_supabase"."acknowledgement_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "principal_type" text not null check ("principal_type" in ('user', 'team', 'role')),
  "principal_id" text not null check (length("principal_id") between 1 and 200),
  "due_in_days" integer check ("due_in_days" is null or ("due_in_days" >= 1 and "due_in_days" <= 365)),
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id")
);
create index if not exists "acknowledgement_assignments_principal_idx" on "better_supabase"."acknowledgement_assignments" ("tenant_id", "principal_type", "principal_id");
alter table "better_supabase"."acknowledgement_assignments" enable row level security;
revoke all on "better_supabase"."acknowledgement_assignments" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgement_assignments" to authenticated;
grant all on "better_supabase"."acknowledgement_assignments" to service_role;
drop policy if exists acknowledgement_assignments_read on "better_supabase"."acknowledgement_assignments";
create policy acknowledgement_assignments_read on "better_supabase"."acknowledgement_assignments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- One row per member and version of a record they acknowledged.
create table if not exists "better_supabase"."acknowledgements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null references "better_supabase"."versions" ("id") on delete restrict,
  "user_id" uuid not null,
  "method" text not null default 'click' check ("method" in ('click', 'signature')),
  "signature_id" uuid,
  "acknowledged_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "version_id", "user_id")
);
create index if not exists "acknowledgements_user_idx" on "better_supabase"."acknowledgements" ("tenant_id", "user_id");
create index if not exists "acknowledgements_version_idx" on "better_supabase"."acknowledgements" ("version_id", "subject_type", "subject_id");
alter table "better_supabase"."acknowledgements" enable row level security;
revoke all on "better_supabase"."acknowledgements" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgements" to authenticated;
grant all on "better_supabase"."acknowledgements" to service_role;
drop policy if exists acknowledgements_read on "better_supabase"."acknowledgements";
create policy acknowledgements_read on "better_supabase"."acknowledgements"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- Which member notify_due_acknowledgements reminded about which version, so
-- each overdue version notifies a member once.
create table if not exists "better_supabase"."acknowledgement_notices" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null,
  "user_id" uuid not null,
  "notified_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "version_id", "user_id")
);
alter table "better_supabase"."acknowledgement_notices" enable row level security;
revoke all on "better_supabase"."acknowledgement_notices" from public, anon, authenticated;
grant all on "better_supabase"."acknowledgement_notices" to service_role;

-- The version of a record members acknowledge: the record's version column
-- (on.<type>.versionColumn), otherwise its latest frozen version.
create or replace function "better_supabase"."current_acknowledgement_version"(tenant uuid, subject_type text, subject_id text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (
    select x."id" from "better_supabase"."versions" x
    where x."tenant_id" = current_acknowledgement_version.tenant
      and x."subject_type" = current_acknowledgement_version.subject_type
      and x."subject_id" = current_acknowledgement_version.subject_id
      and x."frozen"
    order by x."number" desc
    limit 1
  );
end;
$$;
revoke execute on function "better_supabase"."current_acknowledgement_version"(uuid, text, text) from public, anon, authenticated;

-- Writes an assignment without checking the caller, for assign_acknowledgement
-- and for blocks that assign their own records after their own check (the
-- compliance policies). Assigning the same principal again updates its due
-- period.
create or replace function "better_supabase"."place_acknowledgement_assignment"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
  v_existed boolean;
begin
  select exists (
    select 1 from "better_supabase"."acknowledgement_assignments" x
    where x."tenant_id" = place_acknowledgement_assignment.tenant
      and x."subject_type" = place_acknowledgement_assignment.subject_type
      and x."subject_id" = place_acknowledgement_assignment.subject_id
      and x."principal_type" = place_acknowledgement_assignment.principal_type
      and x."principal_id" = place_acknowledgement_assignment.principal_id
  ) into v_existed;
  insert into "better_supabase"."acknowledgement_assignments" ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id", "due_in_days")
  values (place_acknowledgement_assignment.tenant, place_acknowledgement_assignment.subject_type, place_acknowledgement_assignment.subject_id, place_acknowledgement_assignment.principal_type, place_acknowledgement_assignment.principal_id, place_acknowledgement_assignment.due_in_days)
  on conflict ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id")
  do update set "due_in_days" = excluded."due_in_days"
  returning * into v_row;
  if not v_existed then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."place_acknowledgement_assignment"(uuid, text, text, text, text, integer) from public, anon, authenticated;

-- Removes one principal's assignment without checking the caller, for blocks
-- that manage their own records' assignments. Acknowledgements already given
-- stay.
create or replace function "better_supabase"."drop_acknowledgement_assignment"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
begin
  delete from "better_supabase"."acknowledgement_assignments" x
  where x."tenant_id" = drop_acknowledgement_assignment.tenant
    and x."subject_type" = drop_acknowledgement_assignment.subject_type
    and x."subject_id" = drop_acknowledgement_assignment.subject_id
    and x."principal_type" = drop_acknowledgement_assignment.principal_type
    and x."principal_id" = drop_acknowledgement_assignment.principal_id
  returning * into v_row;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."drop_acknowledgement_assignment"(uuid, text, text, text, text) from public, anon, authenticated;

-- Asks a member, a team or everyone holding a role to acknowledge a record,
-- within due_in_days of each new version. Assigning the same principal again
-- updates its due period.
create or replace function "better_supabase"."assign_acknowledgement"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_assignment jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'acknowledgements.manage'), false) and true)) then
    raise exception 'not allowed to assign acknowledgements on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  if assign_acknowledgement.due_in_days is not null and (assign_acknowledgement.due_in_days < 1 or assign_acknowledgement.due_in_days > 365) then
    raise exception 'due_in_days must be between 1 and 365' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_DUE_INVALID';
  end if;
  if assign_acknowledgement.principal_type = 'user' then
    if not exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = assign_acknowledgement.tenant and m."user_id"::text = assign_acknowledgement.principal_id
    ) then
      raise exception 'the user isn''t a member of this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  elsif assign_acknowledgement.principal_type = 'team' then
    raise exception 'team assignments need the teams module' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  elsif assign_acknowledgement.principal_type = 'role' then
    if not (assign_acknowledgement.principal_id = any (array['owner', 'admin', 'member', 'viewer']::text[])
      or exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = assign_acknowledgement.tenant and m."role" = assign_acknowledgement.principal_id)) then
      raise exception 'the role isn''t a role in this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  else
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_acknowledgement_assignment_create"(uuid, text, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::text)', v_hook::oid::regproc)
        using assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id, assign_acknowledgement.principal_type, assign_acknowledgement.principal_id;
    end if;
  end;
  v_assignment := "better_supabase"."place_acknowledgement_assignment"(
    assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id,
    assign_acknowledgement.principal_type, assign_acknowledgement.principal_id, assign_acknowledgement.due_in_days
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_acknowledgement_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using (v_assignment ->> 'id')::uuid;
    end if;
  end;
  return v_assignment;
end;
$$;
revoke execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) to authenticated, service_role;

-- Removes an assignment. Acknowledgements already given stay.
create or replace function "better_supabase"."unassign_acknowledgement"(assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."acknowledgement_assignments" x where x."id" = unassign_acknowledgement.assignment_id for update;
  if not found then
    raise exception 'acknowledgement assignment not found' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'acknowledgements.manage'), false) and true)) then
    raise exception 'not allowed to remove acknowledgement assignments on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."acknowledgement_assignments" x where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."unassign_acknowledgement"(uuid) from public, anon;
grant execute on function "better_supabase"."unassign_acknowledgement"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_acknowledgement_assignments"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."acknowledgements" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1)
  );
begin
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgement assignments on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'principalType', x."principal_type", 'principalId', x."principal_id", 'dueInDays', x."due_in_days", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."principal_type", x."principal_id"), '[]'::jsonb)
    from "better_supabase"."acknowledgement_assignments" x
    where x."tenant_id" = v_tenant
      and x."subject_type" = list_acknowledgement_assignments.subject_type
      and x."subject_id" = list_acknowledgement_assignments.subject_id
  );
end;
$$;
revoke execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) from public, anon;
grant execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) to authenticated, service_role;

-- The caller acknowledges the record's current version. version_id, when
-- given, must still be the current one; signature_id names the caller's
-- completed signature on it. A second call keeps the first acknowledgement.
create or replace function "better_supabase"."acknowledge"(subject_type text, subject_id text, version_id uuid default null, signature_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant uuid;
  v_version uuid;
  v_row "better_supabase"."acknowledgements"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to acknowledge' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  select x."tenant_id" into v_tenant
    from "better_supabase"."acknowledgement_assignments" x
    join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id" and m."user_id" = v_me
    where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id
      and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
    limit 1;
  if v_tenant is null then
    raise exception 'you aren''t asked to acknowledge this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.acknowledge'), false) and true) then
    raise exception 'not allowed to acknowledge this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledge.subject_type, acknowledge.subject_id);
  if v_version is null then
    raise exception 'the record has no version to acknowledge' using errcode = '55000', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  if acknowledge.version_id is not null and acknowledge.version_id <> v_version then
    raise exception 'the record has a newer version; acknowledge that one' using errcode = '55000', hint = 'ACKNOWLEDGEMENT_VERSION_STALE';
  end if;
  if acknowledge.signature_id is not null then
    raise exception 'acknowledging with a signature needs the signatures module' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_SIGNATURE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_acknowledgement_create"(uuid, text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid, $5::uuid)', v_hook::oid::regproc)
        using v_tenant, acknowledge.subject_type, acknowledge.subject_id, v_version, v_me;
    end if;
  end;
  insert into "better_supabase"."acknowledgements" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id", "method", "signature_id")
  values (v_tenant, acknowledge.subject_type, acknowledge.subject_id, v_version, v_me, case when acknowledge.signature_id is null then 'click' else 'signature' end, acknowledge.signature_id)
  on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing
  returning * into v_row;
  if found then
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_acknowledgement_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  else
    select * into v_row from "better_supabase"."acknowledgements" x
    where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id
      and x."version_id" = v_version and x."user_id" = v_me;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id", 'method', v_row."method", 'signatureId', v_row."signature_id", 'acknowledgedAt', v_row."acknowledged_at");
end;
$$;
revoke execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) to authenticated, service_role;

-- The records the caller is asked to acknowledge in an organization, with the
-- current version, its due date and the caller's acknowledgement of it.
-- pending_only: only the ones the caller hasn't acknowledged yet.
create or replace function "better_supabase"."list_my_acknowledgements"(tenant uuid, pending_only boolean default true)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null or not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = list_my_acknowledgements.tenant and m."user_id" = v_me
  ) then
    raise exception 'not a member of this organization' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'organizationId', list_my_acknowledgements.tenant,
      'subjectType', z.subject_type,
      'subjectId', z.subject_id,
      'subjectTitle', null::text,
      'versionId', z.version_id,
      'dueOn', z.due_on,
      'overdue', k."id" is null and z.due_on is not null and z.due_on < current_date,
      'acknowledgedAt', k."acknowledged_at"
    ) order by k."id" is not null, z.due_on nulls last, z.subject_type, z.subject_id), '[]'::jsonb)
    from (
      select y.subject_type, y.subject_id, y.version_id,
        ((select vv."created_at" from "better_supabase"."versions" vv where vv."id" = y.version_id))::date + y.due_in_days as due_on
      from (
        select q.subject_type, q.subject_id, q.due_in_days,
          "better_supabase"."current_acknowledgement_version"(list_my_acknowledgements.tenant, q.subject_type, q.subject_id) as version_id
        from (
          select x."subject_type" as subject_type, x."subject_id" as subject_id, min(x."due_in_days") as due_in_days
          from "better_supabase"."acknowledgement_assignments" x
          join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id" and m."user_id" = v_me
          where x."tenant_id" = list_my_acknowledgements.tenant and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
          group by x."subject_type", x."subject_id"
        ) q
        where true
      ) y
      where y.version_id is not null
    ) z
    left join "better_supabase"."acknowledgements" k on k."subject_type" = z.subject_type and k."subject_id" = z.subject_id
      and k."version_id" = z.version_id and k."user_id" = v_me
    where not coalesce(list_my_acknowledgements.pending_only, true) or k."id" is null
  );
end;
$$;
revoke execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) to authenticated, service_role;

-- How many assigned members acknowledged the record's current version, and
-- who still has to, with their due date.
create or replace function "better_supabase"."acknowledgement_status"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1)
  );
  v_version uuid;
  v_created timestamptz;
begin
  if v_tenant is null then
    return jsonb_build_object('versionId', null, 'required', 0, 'acknowledged', 0, 'pending', '[]'::jsonb);
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgements of this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledgement_status.subject_type, acknowledgement_status.subject_id);
  select x."created_at" into v_created from "better_supabase"."versions" x where x."id" = v_version;
  return (
    select jsonb_build_object(
      'versionId', v_version,
      'required', count(*),
      'acknowledged', count(k."id"),
      'pending', coalesce(jsonb_agg(jsonb_build_object(
        'userId', c.user_id,
        'dueOn', (v_created)::date + c.due_in_days,
        'overdue', coalesce((v_created)::date + c.due_in_days < current_date, false)
      ) order by (v_created)::date + c.due_in_days nulls last, c.user_id) filter (where k."id" is null), '[]'::jsonb)
    )
    from (select m."user_id" as user_id, min(x."due_in_days") as due_in_days
      from "better_supabase"."acknowledgement_assignments" x
      join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id"
      where x."tenant_id" = v_tenant and x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id
        and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
      group by m."user_id") c
    left join "better_supabase"."acknowledgements" k on k."subject_type" = acknowledgement_status.subject_type and k."subject_id" = acknowledgement_status.subject_id
      and k."version_id" = v_version and k."user_id" = c.user_id
  );
end;
$$;
revoke execute on function "better_supabase"."acknowledgement_status"(text, text) from public, anon;
grant execute on function "better_supabase"."acknowledgement_status"(text, text) to authenticated, service_role;

-- The acknowledgements of one version of a record, default the current one.
create or replace function "better_supabase"."acknowledgements_of"(subject_type text, subject_id text, version_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1)
  );
  v_version uuid;
begin
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgements of this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := coalesce(acknowledgements_of.version_id, "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledgements_of.subject_type, acknowledgements_of.subject_id));
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'versionId', x."version_id", 'userId', x."user_id", 'method', x."method", 'signatureId', x."signature_id", 'acknowledgedAt', x."acknowledged_at") order by x."acknowledged_at"), '[]'::jsonb)
    from "better_supabase"."acknowledgements" x
    where x."tenant_id" = v_tenant
      and x."subject_type" = acknowledgements_of.subject_type
      and x."subject_id" = acknowledgements_of.subject_id
      and x."version_id" = v_version
  );
end;
$$;
revoke execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) to authenticated, service_role;

-- Reports each assigned member past the due date of a record's current
-- version once per version: an acknowledgement.reminded event and, with
-- notifications, a notification. Run it daily from a job.
create or replace function "better_supabase"."notify_due_acknowledgements"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item record;
  v_claims text;
  v_count integer := 0;
begin
  for v_item in
    select y.tenant, y.subject_type, y.subject_id, y.version_id, y.user_id,
      (vv."created_at")::date + y.due_in_days as due_on
    from (
      select q.*, "better_supabase"."current_acknowledgement_version"(q.tenant, q.subject_type, q.subject_id) as version_id
      from (
        select x."tenant_id" as tenant, x."subject_type" as subject_type, x."subject_id" as subject_id,
          m."user_id" as user_id, min(x."due_in_days") as due_in_days
        from "better_supabase"."acknowledgement_assignments" x
        join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id"
        where x."due_in_days" is not null and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
        group by x."tenant_id", x."subject_type", x."subject_id", m."user_id"
      ) q
    ) y
    join "better_supabase"."versions" vv on vv."id" = y.version_id
    where (vv."created_at")::date + y.due_in_days < current_date
      and not exists (
        select 1 from "better_supabase"."acknowledgements" k
        where k."subject_type" = y.subject_type and k."subject_id" = y.subject_id
          and k."version_id" = y.version_id and k."user_id" = y.user_id
      )
      and not exists (
        select 1 from "better_supabase"."acknowledgement_notices" nt
        where nt."subject_type" = y.subject_type and nt."subject_id" = y.subject_id
          and nt."version_id" = y.version_id and nt."user_id" = y.user_id
      )
  loop
    insert into "better_supabase"."acknowledgement_notices" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id")
    values (v_item.tenant, v_item.subject_type, v_item.subject_id, v_item.version_id, v_item.user_id)
    on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing;
    if found then
      null;
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_acknowledgements"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_due_acknowledgements"() to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgement_assignments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_select on "better_supabase"."acknowledgement_assignments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_insert on "better_supabase"."acknowledgement_assignments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_update on "better_supabase"."acknowledgement_assignments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_delete on "better_supabase"."acknowledgement_assignments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_select on "better_supabase"."acknowledgements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_insert on "better_supabase"."acknowledgements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_update on "better_supabase"."acknowledgements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_delete on "better_supabase"."acknowledgements" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_147_acknowledgements.sql
-- better-supabase module: acknowledgements
-- @bsb-block-data acknowledgements
-- @bsb-hash sha256:f804dc1bd56a250af2771946adc718a33fc2dbcbbb8cd45180ca0480d6b11329
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('acknowledgements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_147_acknowledgements.sql
-- better-supabase module: acknowledgements
-- @bsb-block acknowledgements@1 managed
-- @bsb-hash sha256:d2d49a7345b71d5f0719d3ef50866f53ffe4e625a098424a3f3536a482deea1b
-- Members confirm they read the current version of a record: assignments to a member, a team or a role, a due date per assignment, a click or a completed signature, and a reminder once a version is overdue.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgement_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgements";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgement_notices";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Acknowledgements: members confirm they read the current version of a
-- record they are assigned to, directly, through a team or through a role.

-- Who has to acknowledge a record: a member, everyone in a team, or everyone
-- holding a role, with an optional number of days to do it in.
create table if not exists "better_supabase"."acknowledgement_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "principal_type" text not null check ("principal_type" in ('user', 'team', 'role')),
  "principal_id" text not null check (length("principal_id") between 1 and 200),
  "due_in_days" integer check ("due_in_days" is null or ("due_in_days" >= 1 and "due_in_days" <= 365)),
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id")
);
create index if not exists "acknowledgement_assignments_principal_idx" on "better_supabase"."acknowledgement_assignments" ("tenant_id", "principal_type", "principal_id");
alter table "better_supabase"."acknowledgement_assignments" enable row level security;
revoke all on "better_supabase"."acknowledgement_assignments" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgement_assignments" to authenticated;
grant all on "better_supabase"."acknowledgement_assignments" to service_role;
drop policy if exists acknowledgement_assignments_read on "better_supabase"."acknowledgement_assignments";
create policy acknowledgement_assignments_read on "better_supabase"."acknowledgement_assignments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- One row per member and version of a record they acknowledged.
create table if not exists "better_supabase"."acknowledgements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null references "better_supabase"."versions" ("id") on delete restrict,
  "user_id" uuid not null,
  "method" text not null default 'click' check ("method" in ('click', 'signature')),
  "signature_id" uuid,
  "acknowledged_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "version_id", "user_id")
);
create index if not exists "acknowledgements_user_idx" on "better_supabase"."acknowledgements" ("tenant_id", "user_id");
create index if not exists "acknowledgements_version_idx" on "better_supabase"."acknowledgements" ("version_id", "subject_type", "subject_id");
alter table "better_supabase"."acknowledgements" enable row level security;
revoke all on "better_supabase"."acknowledgements" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgements" to authenticated;
grant all on "better_supabase"."acknowledgements" to service_role;
drop policy if exists acknowledgements_read on "better_supabase"."acknowledgements";
create policy acknowledgements_read on "better_supabase"."acknowledgements"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- Which member notify_due_acknowledgements reminded about which version, so
-- each overdue version notifies a member once.
create table if not exists "better_supabase"."acknowledgement_notices" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null,
  "user_id" uuid not null,
  "notified_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "version_id", "user_id")
);
alter table "better_supabase"."acknowledgement_notices" enable row level security;
revoke all on "better_supabase"."acknowledgement_notices" from public, anon, authenticated;
grant all on "better_supabase"."acknowledgement_notices" to service_role;

-- The version of a record members acknowledge: the record's version column
-- (on.<type>.versionColumn), otherwise its latest frozen version.
create or replace function "better_supabase"."current_acknowledgement_version"(tenant uuid, subject_type text, subject_id text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if current_acknowledgement_version.subject_type = 'compliance_policy' then
    return (select s."current_version_id"::uuid from "better_supabase"."policies" s where s."id" = (current_acknowledgement_version.subject_id)::uuid and s."tenant_id" = current_acknowledgement_version.tenant);
  end if;
  return (
    select x."id" from "better_supabase"."versions" x
    where x."tenant_id" = current_acknowledgement_version.tenant
      and x."subject_type" = current_acknowledgement_version.subject_type
      and x."subject_id" = current_acknowledgement_version.subject_id
      and x."frozen"
    order by x."number" desc
    limit 1
  );
end;
$$;
revoke execute on function "better_supabase"."current_acknowledgement_version"(uuid, text, text) from public, anon, authenticated;

-- Writes an assignment without checking the caller, for assign_acknowledgement
-- and for blocks that assign their own records after their own check (the
-- compliance policies). Assigning the same principal again updates its due
-- period.
create or replace function "better_supabase"."place_acknowledgement_assignment"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
  v_existed boolean;
begin
  select exists (
    select 1 from "better_supabase"."acknowledgement_assignments" x
    where x."tenant_id" = place_acknowledgement_assignment.tenant
      and x."subject_type" = place_acknowledgement_assignment.subject_type
      and x."subject_id" = place_acknowledgement_assignment.subject_id
      and x."principal_type" = place_acknowledgement_assignment.principal_type
      and x."principal_id" = place_acknowledgement_assignment.principal_id
  ) into v_existed;
  insert into "better_supabase"."acknowledgement_assignments" ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id", "due_in_days")
  values (place_acknowledgement_assignment.tenant, place_acknowledgement_assignment.subject_type, place_acknowledgement_assignment.subject_id, place_acknowledgement_assignment.principal_type, place_acknowledgement_assignment.principal_id, place_acknowledgement_assignment.due_in_days)
  on conflict ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id")
  do update set "due_in_days" = excluded."due_in_days"
  returning * into v_row;
  if not v_existed then
    perform "better_supabase".emit_event('acknowledgement_assignment.created', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'assignmentId', v_row."id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id"), 'acknowledgement-assignments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/acknowledgements');
  perform better_supabase.audit_event(
    event_type => 'acknowledgement_assignment.created',
    category => 'data',
    target_type => 'acknowledgement_assignment',
    record_id => v_row."id"::text,
    summary => 'asked ' || v_row."principal_type" || ' ' || v_row."principal_id" || ' to acknowledge ' || v_row."subject_type" || ' ' || v_row."subject_id",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'assignmentId', v_row."id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."place_acknowledgement_assignment"(uuid, text, text, text, text, integer) from public, anon, authenticated;

-- Removes one principal's assignment without checking the caller, for blocks
-- that manage their own records' assignments. Acknowledgements already given
-- stay.
create or replace function "better_supabase"."drop_acknowledgement_assignment"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
begin
  delete from "better_supabase"."acknowledgement_assignments" x
  where x."tenant_id" = drop_acknowledgement_assignment.tenant
    and x."subject_type" = drop_acknowledgement_assignment.subject_type
    and x."subject_id" = drop_acknowledgement_assignment.subject_id
    and x."principal_type" = drop_acknowledgement_assignment.principal_type
    and x."principal_id" = drop_acknowledgement_assignment.principal_id
  returning * into v_row;
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('acknowledgement_assignment.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'assignmentId', v_row."id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id"), 'acknowledgement-assignments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/acknowledgements');
  perform better_supabase.audit_event(
    event_type => 'acknowledgement_assignment.deleted',
    category => 'data',
    target_type => 'acknowledgement_assignment',
    record_id => v_row."id"::text,
    summary => 'removed the acknowledgement assignment of ' || v_row."principal_type" || ' ' || v_row."principal_id" || ' on ' || v_row."subject_type" || ' ' || v_row."subject_id",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'assignmentId', v_row."id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."drop_acknowledgement_assignment"(uuid, text, text, text, text) from public, anon, authenticated;

-- Asks a member, a team or everyone holding a role to acknowledge a record,
-- within due_in_days of each new version. Assigning the same principal again
-- updates its due period.
create or replace function "better_supabase"."assign_acknowledgement"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_assignment jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'acknowledgements.manage'), false) and true)) then
    raise exception 'not allowed to assign acknowledgements on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  if assign_acknowledgement.due_in_days is not null and (assign_acknowledgement.due_in_days < 1 or assign_acknowledgement.due_in_days > 365) then
    raise exception 'due_in_days must be between 1 and 365' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_DUE_INVALID';
  end if;
  if assign_acknowledgement.principal_type = 'user' then
    if not exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = assign_acknowledgement.tenant and m."user_id"::text = assign_acknowledgement.principal_id
    ) then
      raise exception 'the user isn''t a member of this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  elsif assign_acknowledgement.principal_type = 'team' then
    if not exists (
      select 1 from "better_supabase"."teams" t
      where t."id"::text = assign_acknowledgement.principal_id
        and t."tenant_id" = assign_acknowledgement.tenant
    ) then
      raise exception 'the team isn''t a team in this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  elsif assign_acknowledgement.principal_type = 'role' then
    if not (assign_acknowledgement.principal_id = any (array['owner', 'admin', 'member', 'viewer']::text[])
      or exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = assign_acknowledgement.tenant and m."role" = assign_acknowledgement.principal_id)) then
      raise exception 'the role isn''t a role in this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  else
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_acknowledgement_assignment_create"(uuid, text, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::text)', v_hook::oid::regproc)
        using assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id, assign_acknowledgement.principal_type, assign_acknowledgement.principal_id;
    end if;
  end;
  v_assignment := "better_supabase"."place_acknowledgement_assignment"(
    assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id,
    assign_acknowledgement.principal_type, assign_acknowledgement.principal_id, assign_acknowledgement.due_in_days
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_acknowledgement_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using (v_assignment ->> 'id')::uuid;
    end if;
  end;
  return v_assignment;
end;
$$;
revoke execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) to authenticated, service_role;

-- Removes an assignment. Acknowledgements already given stay.
create or replace function "better_supabase"."unassign_acknowledgement"(assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."acknowledgement_assignments" x where x."id" = unassign_acknowledgement.assignment_id for update;
  if not found then
    raise exception 'acknowledgement assignment not found' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'acknowledgements.manage'), false) and true)) then
    raise exception 'not allowed to remove acknowledgement assignments on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."acknowledgement_assignments" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('acknowledgement_assignment.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'assignmentId', v_row."id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id"), 'acknowledgement-assignments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/acknowledgements');
  perform better_supabase.audit_event(
    event_type => 'acknowledgement_assignment.deleted',
    category => 'data',
    target_type => 'acknowledgement_assignment',
    record_id => v_row."id"::text,
    summary => 'removed the acknowledgement assignment of ' || v_row."principal_type" || ' ' || v_row."principal_id" || ' on ' || v_row."subject_type" || ' ' || v_row."subject_id",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'assignmentId', v_row."id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."unassign_acknowledgement"(uuid) from public, anon;
grant execute on function "better_supabase"."unassign_acknowledgement"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_acknowledgement_assignments"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."acknowledgements" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1)
  );
begin
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgement assignments on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'principalType', x."principal_type", 'principalId', x."principal_id", 'dueInDays', x."due_in_days", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."principal_type", x."principal_id"), '[]'::jsonb)
    from "better_supabase"."acknowledgement_assignments" x
    where x."tenant_id" = v_tenant
      and x."subject_type" = list_acknowledgement_assignments.subject_type
      and x."subject_id" = list_acknowledgement_assignments.subject_id
  );
end;
$$;
revoke execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) from public, anon;
grant execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) to authenticated, service_role;

-- The caller acknowledges the record's current version. version_id, when
-- given, must still be the current one; signature_id names the caller's
-- completed signature on it. A second call keeps the first acknowledgement.
create or replace function "better_supabase"."acknowledge"(subject_type text, subject_id text, version_id uuid default null, signature_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant uuid;
  v_version uuid;
  v_row "better_supabase"."acknowledgements"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to acknowledge' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  select x."tenant_id" into v_tenant
    from "better_supabase"."acknowledgement_assignments" x
    join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id" and m."user_id" = v_me
    where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id
      and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role")
      or (x."principal_type" = 'team' and exists (
        select 1 from "better_supabase"."team_members" tm
        where tm."tenant_id" = m."organization_id"
          and tm."user_id" = m."user_id"
          and tm."team_id"::text = x."principal_id"
      )))
    limit 1;
  if v_tenant is null then
    raise exception 'you aren''t asked to acknowledge this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.acknowledge'), false) and true) then
    raise exception 'not allowed to acknowledge this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledge.subject_type, acknowledge.subject_id);
  if v_version is null then
    raise exception 'the record has no version to acknowledge' using errcode = '55000', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  if acknowledge.version_id is not null and acknowledge.version_id <> v_version then
    raise exception 'the record has a newer version; acknowledge that one' using errcode = '55000', hint = 'ACKNOWLEDGEMENT_VERSION_STALE';
  end if;
  if acknowledge.signature_id is not null and not exists (
    select 1 from "better_supabase"."signatures" sg
    join "better_supabase"."signature_requests" sr on sr."id" = sg."request_id"
    where sg."id" = acknowledge.signature_id
      and sg."signer" = v_me
      and sr."status" = 'completed'
      and sr."tenant_id" = v_tenant
      and sr."subject_type" = acknowledge.subject_type
      and sr."subject_id" = acknowledge.subject_id
      and sr."version_id" = v_version
  ) then
    raise exception 'the signature isn''t your completed signature on this version' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_SIGNATURE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_acknowledgement_create"(uuid, text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid, $5::uuid)', v_hook::oid::regproc)
        using v_tenant, acknowledge.subject_type, acknowledge.subject_id, v_version, v_me;
    end if;
  end;
  insert into "better_supabase"."acknowledgements" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id", "method", "signature_id")
  values (v_tenant, acknowledge.subject_type, acknowledge.subject_id, v_version, v_me, case when acknowledge.signature_id is null then 'click' else 'signature' end, acknowledge.signature_id)
  on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing
  returning * into v_row;
  if found then
    perform "better_supabase".emit_event('acknowledgement.created', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id"), 'acknowledgements/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/acknowledgements');
  perform better_supabase.audit_event(
    event_type => 'acknowledgement.created',
    category => 'data',
    target_type => 'acknowledgement',
    record_id => v_row."id"::text,
    summary => 'acknowledged ' || v_row."subject_type" || ' ' || v_row."subject_id",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id")
  );
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_acknowledgement_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  else
    select * into v_row from "better_supabase"."acknowledgements" x
    where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id
      and x."version_id" = v_version and x."user_id" = v_me;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id", 'method', v_row."method", 'signatureId', v_row."signature_id", 'acknowledgedAt', v_row."acknowledged_at");
end;
$$;
revoke execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) to authenticated, service_role;

-- The records the caller is asked to acknowledge in an organization, with the
-- current version, its due date and the caller's acknowledgement of it.
-- pending_only: only the ones the caller hasn't acknowledged yet.
create or replace function "better_supabase"."list_my_acknowledgements"(tenant uuid, pending_only boolean default true)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null or not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = list_my_acknowledgements.tenant and m."user_id" = v_me
  ) then
    raise exception 'not a member of this organization' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'organizationId', list_my_acknowledgements.tenant,
      'subjectType', z.subject_type,
      'subjectId', z.subject_id,
      'subjectTitle', "better_supabase"."subject_title"(z.subject_type, z.subject_id),
      'versionId', z.version_id,
      'dueOn', z.due_on,
      'overdue', k."id" is null and z.due_on is not null and z.due_on < current_date,
      'acknowledgedAt', k."acknowledged_at"
    ) order by k."id" is not null, z.due_on nulls last, z.subject_type, z.subject_id), '[]'::jsonb)
    from (
      select y.subject_type, y.subject_id, y.version_id,
        ((select vv."created_at" from "better_supabase"."versions" vv where vv."id" = y.version_id))::date + y.due_in_days as due_on
      from (
        select q.subject_type, q.subject_id, q.due_in_days,
          "better_supabase"."current_acknowledgement_version"(list_my_acknowledgements.tenant, q.subject_type, q.subject_id) as version_id
        from (
          select x."subject_type" as subject_type, x."subject_id" as subject_id, min(x."due_in_days") as due_in_days
          from "better_supabase"."acknowledgement_assignments" x
          join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id" and m."user_id" = v_me
          where x."tenant_id" = list_my_acknowledgements.tenant and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role")
      or (x."principal_type" = 'team' and exists (
        select 1 from "better_supabase"."team_members" tm
        where tm."tenant_id" = m."organization_id"
          and tm."user_id" = m."user_id"
          and tm."team_id"::text = x."principal_id"
      )))
          group by x."subject_type", x."subject_id"
        ) q
        where true
      ) y
      where y.version_id is not null
    ) z
    left join "better_supabase"."acknowledgements" k on k."subject_type" = z.subject_type and k."subject_id" = z.subject_id
      and k."version_id" = z.version_id and k."user_id" = v_me
    where not coalesce(list_my_acknowledgements.pending_only, true) or k."id" is null
  );
end;
$$;
revoke execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) to authenticated, service_role;

-- How many assigned members acknowledged the record's current version, and
-- who still has to, with their due date.
create or replace function "better_supabase"."acknowledgement_status"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1)
  );
  v_version uuid;
  v_created timestamptz;
begin
  if v_tenant is null then
    return jsonb_build_object('versionId', null, 'required', 0, 'acknowledged', 0, 'pending', '[]'::jsonb);
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgements of this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledgement_status.subject_type, acknowledgement_status.subject_id);
  select x."created_at" into v_created from "better_supabase"."versions" x where x."id" = v_version;
  return (
    select jsonb_build_object(
      'versionId', v_version,
      'required', count(*),
      'acknowledged', count(k."id"),
      'pending', coalesce(jsonb_agg(jsonb_build_object(
        'userId', c.user_id,
        'dueOn', (v_created)::date + c.due_in_days,
        'overdue', coalesce((v_created)::date + c.due_in_days < current_date, false)
      ) order by (v_created)::date + c.due_in_days nulls last, c.user_id) filter (where k."id" is null), '[]'::jsonb)
    )
    from (select m."user_id" as user_id, min(x."due_in_days") as due_in_days
      from "better_supabase"."acknowledgement_assignments" x
      join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id"
      where x."tenant_id" = v_tenant and x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id
        and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role")
      or (x."principal_type" = 'team' and exists (
        select 1 from "better_supabase"."team_members" tm
        where tm."tenant_id" = m."organization_id"
          and tm."user_id" = m."user_id"
          and tm."team_id"::text = x."principal_id"
      )))
      group by m."user_id") c
    left join "better_supabase"."acknowledgements" k on k."subject_type" = acknowledgement_status.subject_type and k."subject_id" = acknowledgement_status.subject_id
      and k."version_id" = v_version and k."user_id" = c.user_id
  );
end;
$$;
revoke execute on function "better_supabase"."acknowledgement_status"(text, text) from public, anon;
grant execute on function "better_supabase"."acknowledgement_status"(text, text) to authenticated, service_role;

-- The acknowledgements of one version of a record, default the current one.
create or replace function "better_supabase"."acknowledgements_of"(subject_type text, subject_id text, version_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1)
  );
  v_version uuid;
begin
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgements of this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := coalesce(acknowledgements_of.version_id, "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledgements_of.subject_type, acknowledgements_of.subject_id));
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'versionId', x."version_id", 'userId', x."user_id", 'method', x."method", 'signatureId', x."signature_id", 'acknowledgedAt', x."acknowledged_at") order by x."acknowledged_at"), '[]'::jsonb)
    from "better_supabase"."acknowledgements" x
    where x."tenant_id" = v_tenant
      and x."subject_type" = acknowledgements_of.subject_type
      and x."subject_id" = acknowledgements_of.subject_id
      and x."version_id" = v_version
  );
end;
$$;
revoke execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) to authenticated, service_role;

-- Reports each assigned member past the due date of a record's current
-- version once per version: an acknowledgement.reminded event and, with
-- notifications, a notification. Run it daily from a job.
create or replace function "better_supabase"."notify_due_acknowledgements"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item record;
  v_claims text;
  v_count integer := 0;
begin
  for v_item in
    select y.tenant, y.subject_type, y.subject_id, y.version_id, y.user_id,
      (vv."created_at")::date + y.due_in_days as due_on
    from (
      select q.*, "better_supabase"."current_acknowledgement_version"(q.tenant, q.subject_type, q.subject_id) as version_id
      from (
        select x."tenant_id" as tenant, x."subject_type" as subject_type, x."subject_id" as subject_id,
          m."user_id" as user_id, min(x."due_in_days") as due_in_days
        from "better_supabase"."acknowledgement_assignments" x
        join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id"
        where x."due_in_days" is not null and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role")
      or (x."principal_type" = 'team' and exists (
        select 1 from "better_supabase"."team_members" tm
        where tm."tenant_id" = m."organization_id"
          and tm."user_id" = m."user_id"
          and tm."team_id"::text = x."principal_id"
      )))
        group by x."tenant_id", x."subject_type", x."subject_id", m."user_id"
      ) q
    ) y
    join "better_supabase"."versions" vv on vv."id" = y.version_id
    where (vv."created_at")::date + y.due_in_days < current_date
      and not exists (
        select 1 from "better_supabase"."acknowledgements" k
        where k."subject_type" = y.subject_type and k."subject_id" = y.subject_id
          and k."version_id" = y.version_id and k."user_id" = y.user_id
      )
      and not exists (
        select 1 from "better_supabase"."acknowledgement_notices" nt
        where nt."subject_type" = y.subject_type and nt."subject_id" = y.subject_id
          and nt."version_id" = y.version_id and nt."user_id" = y.user_id
      )
  loop
    insert into "better_supabase"."acknowledgement_notices" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id")
    values (v_item.tenant, v_item.subject_type, v_item.subject_id, v_item.version_id, v_item.user_id)
    on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing;
    if found then
      perform "better_supabase".emit_event('acknowledgement.reminded', jsonb_build_object('organizationId', v_item.tenant, 'subjectType', v_item.subject_type, 'subjectId', v_item.subject_id, 'versionId', v_item.version_id, 'userId', v_item.user_id, 'dueOn', v_item.due_on), 'acknowledgements/' || v_item.subject_type || '/' || v_item.subject_id, (v_item.tenant)::text, null, 'better-supabase/acknowledgements');
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'acknowledgement.reminded',
      'tenant', v_item.tenant,
      'actor', null,
      'subject_type', v_item.subject_type,
      'subject_id', v_item.subject_id,
      'summary', coalesce("better_supabase"."subject_title"(v_item.subject_type, v_item.subject_id), v_item.subject_type),
      'recipients', to_jsonb(array[v_item.user_id]),
      'key', 'acknowledgement.reminded:' || v_item.subject_type || ':' || v_item.subject_id || ':' || v_item.version_id::text || ':' || v_item.user_id::text,
      'data', jsonb_build_object('versionId', v_item.version_id, 'dueOn', v_item.due_on)
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_acknowledgements"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_due_acknowledgements"() to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgement_assignments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_select on "better_supabase"."acknowledgement_assignments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_insert on "better_supabase"."acknowledgement_assignments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_update on "better_supabase"."acknowledgement_assignments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_delete on "better_supabase"."acknowledgement_assignments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_select on "better_supabase"."acknowledgements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_insert on "better_supabase"."acknowledgements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_update on "better_supabase"."acknowledgements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_delete on "better_supabase"."acknowledgements" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_147_acknowledgements.sql
-- better-supabase module: acknowledgements
-- @bsb-block-data acknowledgements
-- @bsb-hash sha256:f804dc1bd56a250af2771946adc718a33fc2dbcbbb8cd45180ca0480d6b11329
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('acknowledgements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_147_acknowledgements.sql
-- better-supabase module: acknowledgements
-- @bsb-block acknowledgements@1 managed
-- @bsb-hash sha256:df87bf412c1bff720c14386be916c3f5e175baedbe21a59bb4a00473e309e196
-- Members confirm they read the current version of a record: assignments to a member, a team or a role, a due date per assignment, a click or a completed signature, and a reminder once a version is overdue.
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
    drop policy if exists bsb_tenant_scope on "app_private"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_select on "app_private"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_update on "app_private"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."acknowledgement_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."acknowledgements";
    drop policy if exists bsb_tenant_scope_select on "app_private"."acknowledgements";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."acknowledgements";
    drop policy if exists bsb_tenant_scope_update on "app_private"."acknowledgements";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."acknowledgements";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_select on "app_private"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_update on "app_private"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."acknowledgement_notices";
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
-- Acknowledgements: members confirm they read the current version of a
-- record they are assigned to, directly, through a team or through a role.

-- Who has to acknowledge a record: a member, everyone in a team, or everyone
-- holding a role, with an optional number of days to do it in.
create table if not exists "app_private"."acknowledgement_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "principal_type" text not null check ("principal_type" in ('user', 'team', 'role')),
  "principal_id" text not null check (length("principal_id") between 1 and 200),
  "due_in_days" integer check ("due_in_days" is null or ("due_in_days" >= 1 and "due_in_days" <= 365)),
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id")
);
create index if not exists "acknowledgement_assignments_principal_idx" on "app_private"."acknowledgement_assignments" ("tenant_id", "principal_type", "principal_id");
alter table "app_private"."acknowledgement_assignments" enable row level security;
revoke all on "app_private"."acknowledgement_assignments" from public, anon, authenticated;
grant select on "app_private"."acknowledgement_assignments" to authenticated;
grant all on "app_private"."acknowledgement_assignments" to service_role;
drop policy if exists acknowledgement_assignments_read on "app_private"."acknowledgement_assignments";
create policy acknowledgement_assignments_read on "app_private"."acknowledgement_assignments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- One row per member and version of a record they acknowledged.
create table if not exists "app_private"."acknowledgements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null references "better_supabase"."versions" ("id") on delete restrict,
  "user_id" uuid not null,
  "method" text not null default 'click' check ("method" in ('click', 'signature')),
  "signature_id" uuid,
  "acknowledged_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "version_id", "user_id")
);
create index if not exists "acknowledgements_user_idx" on "app_private"."acknowledgements" ("tenant_id", "user_id");
create index if not exists "acknowledgements_version_idx" on "app_private"."acknowledgements" ("version_id", "subject_type", "subject_id");
alter table "app_private"."acknowledgements" enable row level security;
revoke all on "app_private"."acknowledgements" from public, anon, authenticated;
grant select on "app_private"."acknowledgements" to authenticated;
grant all on "app_private"."acknowledgements" to service_role;
drop policy if exists acknowledgements_read on "app_private"."acknowledgements";
create policy acknowledgements_read on "app_private"."acknowledgements"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- Which member notify_due_acknowledgements reminded about which version, so
-- each overdue version notifies a member once.
create table if not exists "app_private"."acknowledgement_notices" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null,
  "user_id" uuid not null,
  "notified_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "version_id", "user_id")
);
alter table "app_private"."acknowledgement_notices" enable row level security;
revoke all on "app_private"."acknowledgement_notices" from public, anon, authenticated;
grant all on "app_private"."acknowledgement_notices" to service_role;

-- The version of a record members acknowledge: the record's version column
-- (on.<type>.versionColumn), otherwise its latest frozen version.
create or replace function "app_private"."current_acknowledgement_version"(tenant uuid, subject_type text, subject_id text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (
    select x."id" from "better_supabase"."versions" x
    where x."tenant_id" = current_acknowledgement_version.tenant
      and x."subject_type" = current_acknowledgement_version.subject_type
      and x."subject_id" = current_acknowledgement_version.subject_id
      and x."frozen"
    order by x."number" desc
    limit 1
  );
end;
$$;
revoke execute on function "app_private"."current_acknowledgement_version"(uuid, text, text) from public, anon, authenticated;

-- Writes an assignment without checking the caller, for assign_acknowledgement
-- and for blocks that assign their own records after their own check (the
-- compliance policies). Assigning the same principal again updates its due
-- period.
create or replace function "app_private"."place_acknowledgement_assignment"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."acknowledgement_assignments"%rowtype;
  v_existed boolean;
begin
  select exists (
    select 1 from "app_private"."acknowledgement_assignments" x
    where x."tenant_id" = place_acknowledgement_assignment.tenant
      and x."subject_type" = place_acknowledgement_assignment.subject_type
      and x."subject_id" = place_acknowledgement_assignment.subject_id
      and x."principal_type" = place_acknowledgement_assignment.principal_type
      and x."principal_id" = place_acknowledgement_assignment.principal_id
  ) into v_existed;
  insert into "app_private"."acknowledgement_assignments" ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id", "due_in_days")
  values (place_acknowledgement_assignment.tenant, place_acknowledgement_assignment.subject_type, place_acknowledgement_assignment.subject_id, place_acknowledgement_assignment.principal_type, place_acknowledgement_assignment.principal_id, place_acknowledgement_assignment.due_in_days)
  on conflict ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id")
  do update set "due_in_days" = excluded."due_in_days"
  returning * into v_row;
  if not v_existed then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."place_acknowledgement_assignment"(uuid, text, text, text, text, integer) from public, anon, authenticated;

-- Removes one principal's assignment without checking the caller, for blocks
-- that manage their own records' assignments. Acknowledgements already given
-- stay.
create or replace function "app_private"."drop_acknowledgement_assignment"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."acknowledgement_assignments"%rowtype;
begin
  delete from "app_private"."acknowledgement_assignments" x
  where x."tenant_id" = drop_acknowledgement_assignment.tenant
    and x."subject_type" = drop_acknowledgement_assignment.subject_type
    and x."subject_id" = drop_acknowledgement_assignment.subject_id
    and x."principal_type" = drop_acknowledgement_assignment.principal_type
    and x."principal_id" = drop_acknowledgement_assignment.principal_id
  returning * into v_row;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."drop_acknowledgement_assignment"(uuid, text, text, text, text) from public, anon, authenticated;

-- Asks a member, a team or everyone holding a role to acknowledge a record,
-- within due_in_days of each new version. Assigning the same principal again
-- updates its due period.
create or replace function "app_private"."assign_acknowledgement"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_assignment jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'acknowledgements.manage'), false) and true)) then
    raise exception 'not allowed to assign acknowledgements on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  if assign_acknowledgement.due_in_days is not null and (assign_acknowledgement.due_in_days < 1 or assign_acknowledgement.due_in_days > 365) then
    raise exception 'due_in_days must be between 1 and 365' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_DUE_INVALID';
  end if;
  if assign_acknowledgement.principal_type = 'user' then
    if not exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = assign_acknowledgement.tenant and m."user_id"::text = assign_acknowledgement.principal_id
    ) then
      raise exception 'the user isn''t a member of this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  elsif assign_acknowledgement.principal_type = 'team' then
    raise exception 'team assignments need the teams module' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  elsif assign_acknowledgement.principal_type = 'role' then
    if not (assign_acknowledgement.principal_id = any (array['owner', 'admin', 'member', 'viewer']::text[])
      or exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = assign_acknowledgement.tenant and m."role" = assign_acknowledgement.principal_id)) then
      raise exception 'the role isn''t a role in this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  else
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_acknowledgement_assignment_create"(uuid, text, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::text)', v_hook::oid::regproc)
        using assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id, assign_acknowledgement.principal_type, assign_acknowledgement.principal_id;
    end if;
  end;
  v_assignment := "app_private"."place_acknowledgement_assignment"(
    assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id,
    assign_acknowledgement.principal_type, assign_acknowledgement.principal_id, assign_acknowledgement.due_in_days
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_acknowledgement_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using (v_assignment ->> 'id')::uuid;
    end if;
  end;
  return v_assignment;
end;
$$;
revoke execute on function "app_private"."assign_acknowledgement"(uuid, text, text, text, text, integer) from public, anon;
grant execute on function "app_private"."assign_acknowledgement"(uuid, text, text, text, text, integer) to authenticated, service_role;

-- Removes an assignment. Acknowledgements already given stay.
create or replace function "app_private"."unassign_acknowledgement"(assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."acknowledgement_assignments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."acknowledgement_assignments" x where x."id" = unassign_acknowledgement.assignment_id for update;
  if not found then
    raise exception 'acknowledgement assignment not found' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'acknowledgements.manage'), false) and true)) then
    raise exception 'not allowed to remove acknowledgement assignments on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  delete from "app_private"."acknowledgement_assignments" x where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."unassign_acknowledgement"(uuid) from public, anon;
grant execute on function "app_private"."unassign_acknowledgement"(uuid) to authenticated, service_role;

create or replace function "app_private"."list_acknowledgement_assignments"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "app_private"."acknowledgement_assignments" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1),
    (select x."tenant_id" from "app_private"."acknowledgements" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1)
  );
begin
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgement assignments on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'principalType', x."principal_type", 'principalId', x."principal_id", 'dueInDays', x."due_in_days", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."principal_type", x."principal_id"), '[]'::jsonb)
    from "app_private"."acknowledgement_assignments" x
    where x."tenant_id" = v_tenant
      and x."subject_type" = list_acknowledgement_assignments.subject_type
      and x."subject_id" = list_acknowledgement_assignments.subject_id
  );
end;
$$;
revoke execute on function "app_private"."list_acknowledgement_assignments"(text, text) from public, anon;
grant execute on function "app_private"."list_acknowledgement_assignments"(text, text) to authenticated, service_role;

-- The caller acknowledges the record's current version. version_id, when
-- given, must still be the current one; signature_id names the caller's
-- completed signature on it. A second call keeps the first acknowledgement.
create or replace function "app_private"."acknowledge"(subject_type text, subject_id text, version_id uuid default null, signature_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant uuid;
  v_version uuid;
  v_row "app_private"."acknowledgements"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to acknowledge' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  select x."tenant_id" into v_tenant
    from "app_private"."acknowledgement_assignments" x
    join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id" and m."user_id" = v_me
    where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id
      and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
    limit 1;
  if v_tenant is null then
    raise exception 'you aren''t asked to acknowledge this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.acknowledge'), false) and true) then
    raise exception 'not allowed to acknowledge this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "app_private"."current_acknowledgement_version"(v_tenant, acknowledge.subject_type, acknowledge.subject_id);
  if v_version is null then
    raise exception 'the record has no version to acknowledge' using errcode = '55000', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  if acknowledge.version_id is not null and acknowledge.version_id <> v_version then
    raise exception 'the record has a newer version; acknowledge that one' using errcode = '55000', hint = 'ACKNOWLEDGEMENT_VERSION_STALE';
  end if;
  if acknowledge.signature_id is not null then
    raise exception 'acknowledging with a signature needs the signatures module' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_SIGNATURE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_acknowledgement_create"(uuid, text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid, $5::uuid)', v_hook::oid::regproc)
        using v_tenant, acknowledge.subject_type, acknowledge.subject_id, v_version, v_me;
    end if;
  end;
  insert into "app_private"."acknowledgements" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id", "method", "signature_id")
  values (v_tenant, acknowledge.subject_type, acknowledge.subject_id, v_version, v_me, case when acknowledge.signature_id is null then 'click' else 'signature' end, acknowledge.signature_id)
  on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing
  returning * into v_row;
  if found then
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_acknowledgement_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  else
    select * into v_row from "app_private"."acknowledgements" x
    where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id
      and x."version_id" = v_version and x."user_id" = v_me;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id", 'method', v_row."method", 'signatureId', v_row."signature_id", 'acknowledgedAt', v_row."acknowledged_at");
end;
$$;
revoke execute on function "app_private"."acknowledge"(text, text, uuid, uuid) from public, anon;
grant execute on function "app_private"."acknowledge"(text, text, uuid, uuid) to authenticated, service_role;

-- The records the caller is asked to acknowledge in an organization, with the
-- current version, its due date and the caller's acknowledgement of it.
-- pending_only: only the ones the caller hasn't acknowledged yet.
create or replace function "app_private"."list_my_acknowledgements"(tenant uuid, pending_only boolean default true)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null or not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = list_my_acknowledgements.tenant and m."user_id" = v_me
  ) then
    raise exception 'not a member of this organization' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'organizationId', list_my_acknowledgements.tenant,
      'subjectType', z.subject_type,
      'subjectId', z.subject_id,
      'subjectTitle', null::text,
      'versionId', z.version_id,
      'dueOn', z.due_on,
      'overdue', k."id" is null and z.due_on is not null and z.due_on < current_date,
      'acknowledgedAt', k."acknowledged_at"
    ) order by k."id" is not null, z.due_on nulls last, z.subject_type, z.subject_id), '[]'::jsonb)
    from (
      select y.subject_type, y.subject_id, y.version_id,
        ((select vv."created_at" from "better_supabase"."versions" vv where vv."id" = y.version_id))::date + y.due_in_days as due_on
      from (
        select q.subject_type, q.subject_id, q.due_in_days,
          "app_private"."current_acknowledgement_version"(list_my_acknowledgements.tenant, q.subject_type, q.subject_id) as version_id
        from (
          select x."subject_type" as subject_type, x."subject_id" as subject_id, min(x."due_in_days") as due_in_days
          from "app_private"."acknowledgement_assignments" x
          join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id" and m."user_id" = v_me
          where x."tenant_id" = list_my_acknowledgements.tenant and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
          group by x."subject_type", x."subject_id"
        ) q
        where true
      ) y
      where y.version_id is not null
    ) z
    left join "app_private"."acknowledgements" k on k."subject_type" = z.subject_type and k."subject_id" = z.subject_id
      and k."version_id" = z.version_id and k."user_id" = v_me
    where not coalesce(list_my_acknowledgements.pending_only, true) or k."id" is null
  );
end;
$$;
revoke execute on function "app_private"."list_my_acknowledgements"(uuid, boolean) from public, anon;
grant execute on function "app_private"."list_my_acknowledgements"(uuid, boolean) to authenticated, service_role;

-- How many assigned members acknowledged the record's current version, and
-- who still has to, with their due date.
create or replace function "app_private"."acknowledgement_status"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "app_private"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1),
    (select x."tenant_id" from "app_private"."acknowledgements" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1)
  );
  v_version uuid;
  v_created timestamptz;
begin
  if v_tenant is null then
    return jsonb_build_object('versionId', null, 'required', 0, 'acknowledged', 0, 'pending', '[]'::jsonb);
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgements of this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "app_private"."current_acknowledgement_version"(v_tenant, acknowledgement_status.subject_type, acknowledgement_status.subject_id);
  select x."created_at" into v_created from "better_supabase"."versions" x where x."id" = v_version;
  return (
    select jsonb_build_object(
      'versionId', v_version,
      'required', count(*),
      'acknowledged', count(k."id"),
      'pending', coalesce(jsonb_agg(jsonb_build_object(
        'userId', c.user_id,
        'dueOn', (v_created)::date + c.due_in_days,
        'overdue', coalesce((v_created)::date + c.due_in_days < current_date, false)
      ) order by (v_created)::date + c.due_in_days nulls last, c.user_id) filter (where k."id" is null), '[]'::jsonb)
    )
    from (select m."user_id" as user_id, min(x."due_in_days") as due_in_days
      from "app_private"."acknowledgement_assignments" x
      join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id"
      where x."tenant_id" = v_tenant and x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id
        and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
      group by m."user_id") c
    left join "app_private"."acknowledgements" k on k."subject_type" = acknowledgement_status.subject_type and k."subject_id" = acknowledgement_status.subject_id
      and k."version_id" = v_version and k."user_id" = c.user_id
  );
end;
$$;
revoke execute on function "app_private"."acknowledgement_status"(text, text) from public, anon;
grant execute on function "app_private"."acknowledgement_status"(text, text) to authenticated, service_role;

-- The acknowledgements of one version of a record, default the current one.
create or replace function "app_private"."acknowledgements_of"(subject_type text, subject_id text, version_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "app_private"."acknowledgement_assignments" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1),
    (select x."tenant_id" from "app_private"."acknowledgements" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1)
  );
  v_version uuid;
begin
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgements of this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := coalesce(acknowledgements_of.version_id, "app_private"."current_acknowledgement_version"(v_tenant, acknowledgements_of.subject_type, acknowledgements_of.subject_id));
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'versionId', x."version_id", 'userId', x."user_id", 'method', x."method", 'signatureId', x."signature_id", 'acknowledgedAt', x."acknowledged_at") order by x."acknowledged_at"), '[]'::jsonb)
    from "app_private"."acknowledgements" x
    where x."tenant_id" = v_tenant
      and x."subject_type" = acknowledgements_of.subject_type
      and x."subject_id" = acknowledgements_of.subject_id
      and x."version_id" = v_version
  );
end;
$$;
revoke execute on function "app_private"."acknowledgements_of"(text, text, uuid) from public, anon;
grant execute on function "app_private"."acknowledgements_of"(text, text, uuid) to authenticated, service_role;

-- Reports each assigned member past the due date of a record's current
-- version once per version: an acknowledgement.reminded event and, with
-- notifications, a notification. Run it daily from a job.
create or replace function "app_private"."notify_due_acknowledgements"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item record;
  v_claims text;
  v_count integer := 0;
begin
  for v_item in
    select y.tenant, y.subject_type, y.subject_id, y.version_id, y.user_id,
      (vv."created_at")::date + y.due_in_days as due_on
    from (
      select q.*, "app_private"."current_acknowledgement_version"(q.tenant, q.subject_type, q.subject_id) as version_id
      from (
        select x."tenant_id" as tenant, x."subject_type" as subject_type, x."subject_id" as subject_id,
          m."user_id" as user_id, min(x."due_in_days") as due_in_days
        from "app_private"."acknowledgement_assignments" x
        join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id"
        where x."due_in_days" is not null and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
        group by x."tenant_id", x."subject_type", x."subject_id", m."user_id"
      ) q
    ) y
    join "better_supabase"."versions" vv on vv."id" = y.version_id
    where (vv."created_at")::date + y.due_in_days < current_date
      and not exists (
        select 1 from "app_private"."acknowledgements" k
        where k."subject_type" = y.subject_type and k."subject_id" = y.subject_id
          and k."version_id" = y.version_id and k."user_id" = y.user_id
      )
      and not exists (
        select 1 from "app_private"."acknowledgement_notices" nt
        where nt."subject_type" = y.subject_type and nt."subject_id" = y.subject_id
          and nt."version_id" = y.version_id and nt."user_id" = y.user_id
      )
  loop
    insert into "app_private"."acknowledgement_notices" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id")
    values (v_item.tenant, v_item.subject_type, v_item.subject_id, v_item.version_id, v_item.user_id)
    on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing;
    if found then
      null;
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."notify_due_acknowledgements"() from public, anon, authenticated;
grant execute on function "app_private"."notify_due_acknowledgements"() to service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."acknowledgement_assignments";
drop policy if exists bsb_tenant_scope_select on "app_private"."acknowledgement_assignments";
create policy bsb_tenant_scope_select on "app_private"."acknowledgement_assignments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."acknowledgement_assignments";
create policy bsb_tenant_scope_insert on "app_private"."acknowledgement_assignments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."acknowledgement_assignments";
create policy bsb_tenant_scope_update on "app_private"."acknowledgement_assignments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."acknowledgement_assignments";
create policy bsb_tenant_scope_delete on "app_private"."acknowledgement_assignments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."acknowledgements";
drop policy if exists bsb_tenant_scope_select on "app_private"."acknowledgements";
create policy bsb_tenant_scope_select on "app_private"."acknowledgements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."acknowledgements";
create policy bsb_tenant_scope_insert on "app_private"."acknowledgements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."acknowledgements";
create policy bsb_tenant_scope_update on "app_private"."acknowledgements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."acknowledgements";
create policy bsb_tenant_scope_delete on "app_private"."acknowledgements" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_147_acknowledgements.sql
-- better-supabase module: acknowledgements
-- @bsb-block-data acknowledgements
-- @bsb-hash sha256:f804dc1bd56a250af2771946adc718a33fc2dbcbbb8cd45180ca0480d6b11329
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('acknowledgements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_147_acknowledgements.sql
-- better-supabase module: acknowledgements
-- @bsb-block acknowledgements@1 managed
-- @bsb-hash sha256:130c5bd29692b8ea0224b7ad57ab42804a8cabf79c8e06772d7a0702b3b6f252
-- Members confirm they read the current version of a record: assignments to a member, a team or a role, a due date per assignment, a click or a completed signature, and a reminder once a version is overdue.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgement_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgements";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgement_notices";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Acknowledgements: members confirm they read the current version of a
-- record they are assigned to, directly, through a team or through a role.

-- Who has to acknowledge a record: a member, everyone in a team, or everyone
-- holding a role, with an optional number of days to do it in.
create table if not exists "better_supabase"."acknowledgement_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "principal_type" text not null check ("principal_type" in ('user', 'team', 'role')),
  "principal_id" text not null check (length("principal_id") between 1 and 200),
  "due_in_days" integer check ("due_in_days" is null or ("due_in_days" >= 1 and "due_in_days" <= 365)),
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id")
);
create index if not exists "acknowledgement_assignments_principal_idx" on "better_supabase"."acknowledgement_assignments" ("tenant_id", "principal_type", "principal_id");
alter table "better_supabase"."acknowledgement_assignments" enable row level security;
revoke all on "better_supabase"."acknowledgement_assignments" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgement_assignments" to authenticated;
grant all on "better_supabase"."acknowledgement_assignments" to service_role;
drop policy if exists acknowledgement_assignments_read on "better_supabase"."acknowledgement_assignments";
create policy acknowledgement_assignments_read on "better_supabase"."acknowledgement_assignments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- One row per member and version of a record they acknowledged.
create table if not exists "better_supabase"."acknowledgements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null references "better_supabase"."versions" ("id") on delete restrict,
  "user_id" uuid not null,
  "method" text not null default 'click' check ("method" in ('click', 'signature')),
  "signature_id" uuid,
  "acknowledged_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "version_id", "user_id")
);
create index if not exists "acknowledgements_user_idx" on "better_supabase"."acknowledgements" ("tenant_id", "user_id");
create index if not exists "acknowledgements_version_idx" on "better_supabase"."acknowledgements" ("version_id", "subject_type", "subject_id");
alter table "better_supabase"."acknowledgements" enable row level security;
revoke all on "better_supabase"."acknowledgements" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgements" to authenticated;
grant all on "better_supabase"."acknowledgements" to service_role;
drop policy if exists acknowledgements_read on "better_supabase"."acknowledgements";
create policy acknowledgements_read on "better_supabase"."acknowledgements"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- Which member notify_due_acknowledgements reminded about which version, so
-- each overdue version notifies a member once.
create table if not exists "better_supabase"."acknowledgement_notices" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null,
  "user_id" uuid not null,
  "notified_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "version_id", "user_id")
);
alter table "better_supabase"."acknowledgement_notices" enable row level security;
revoke all on "better_supabase"."acknowledgement_notices" from public, anon, authenticated;
grant all on "better_supabase"."acknowledgement_notices" to service_role;

-- The version of a record members acknowledge: the record's version column
-- (on.<type>.versionColumn), otherwise its latest frozen version.
create or replace function "better_supabase"."current_acknowledgement_version"(tenant uuid, subject_type text, subject_id text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (
    select x."id" from "better_supabase"."versions" x
    where x."tenant_id" = current_acknowledgement_version.tenant
      and x."subject_type" = current_acknowledgement_version.subject_type
      and x."subject_id" = current_acknowledgement_version.subject_id
      and x."frozen"
    order by x."number" desc
    limit 1
  );
end;
$$;
revoke execute on function "better_supabase"."current_acknowledgement_version"(uuid, text, text) from public, anon, authenticated;

-- Writes an assignment without checking the caller, for assign_acknowledgement
-- and for blocks that assign their own records after their own check (the
-- compliance policies). Assigning the same principal again updates its due
-- period.
create or replace function "better_supabase"."place_acknowledgement_assignment"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
  v_existed boolean;
begin
  select exists (
    select 1 from "better_supabase"."acknowledgement_assignments" x
    where x."tenant_id" = place_acknowledgement_assignment.tenant
      and x."subject_type" = place_acknowledgement_assignment.subject_type
      and x."subject_id" = place_acknowledgement_assignment.subject_id
      and x."principal_type" = place_acknowledgement_assignment.principal_type
      and x."principal_id" = place_acknowledgement_assignment.principal_id
  ) into v_existed;
  insert into "better_supabase"."acknowledgement_assignments" ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id", "due_in_days")
  values (place_acknowledgement_assignment.tenant, place_acknowledgement_assignment.subject_type, place_acknowledgement_assignment.subject_id, place_acknowledgement_assignment.principal_type, place_acknowledgement_assignment.principal_id, place_acknowledgement_assignment.due_in_days)
  on conflict ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id")
  do update set "due_in_days" = excluded."due_in_days"
  returning * into v_row;
  if not v_existed then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."place_acknowledgement_assignment"(uuid, text, text, text, text, integer) from public, anon, authenticated;

-- Removes one principal's assignment without checking the caller, for blocks
-- that manage their own records' assignments. Acknowledgements already given
-- stay.
create or replace function "better_supabase"."drop_acknowledgement_assignment"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
begin
  delete from "better_supabase"."acknowledgement_assignments" x
  where x."tenant_id" = drop_acknowledgement_assignment.tenant
    and x."subject_type" = drop_acknowledgement_assignment.subject_type
    and x."subject_id" = drop_acknowledgement_assignment.subject_id
    and x."principal_type" = drop_acknowledgement_assignment.principal_type
    and x."principal_id" = drop_acknowledgement_assignment.principal_id
  returning * into v_row;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."drop_acknowledgement_assignment"(uuid, text, text, text, text) from public, anon, authenticated;

-- Asks a member, a team or everyone holding a role to acknowledge a record,
-- within due_in_days of each new version. Assigning the same principal again
-- updates its due period.
create or replace function "better_supabase"."assign_acknowledgement"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_assignment jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'acknowledgements.manage'), false) and true)) then
    raise exception 'not allowed to assign acknowledgements on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  if assign_acknowledgement.due_in_days is not null and (assign_acknowledgement.due_in_days < 1 or assign_acknowledgement.due_in_days > 365) then
    raise exception 'due_in_days must be between 1 and 365' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_DUE_INVALID';
  end if;
  if assign_acknowledgement.principal_type = 'user' then
    if not exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = assign_acknowledgement.tenant and m."user_id"::text = assign_acknowledgement.principal_id
    ) then
      raise exception 'the user isn''t a member of this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  elsif assign_acknowledgement.principal_type = 'team' then
    raise exception 'team assignments need the teams module' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  elsif assign_acknowledgement.principal_type = 'role' then
    if not (assign_acknowledgement.principal_id = any (array['owner', 'admin', 'member', 'viewer']::text[])
      or exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = assign_acknowledgement.tenant and m."role" = assign_acknowledgement.principal_id)) then
      raise exception 'the role isn''t a role in this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  else
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_acknowledgement_assignment_create"(uuid, text, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::text)', v_hook::oid::regproc)
        using assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id, assign_acknowledgement.principal_type, assign_acknowledgement.principal_id;
    end if;
  end;
  v_assignment := "better_supabase"."place_acknowledgement_assignment"(
    assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id,
    assign_acknowledgement.principal_type, assign_acknowledgement.principal_id, assign_acknowledgement.due_in_days
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_acknowledgement_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using (v_assignment ->> 'id')::uuid;
    end if;
  end;
  return v_assignment;
end;
$$;
revoke execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) to authenticated, service_role;

-- Removes an assignment. Acknowledgements already given stay.
create or replace function "better_supabase"."unassign_acknowledgement"(assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."acknowledgement_assignments" x where x."id" = unassign_acknowledgement.assignment_id for update;
  if not found then
    raise exception 'acknowledgement assignment not found' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'acknowledgements.manage'), false) and true)) then
    raise exception 'not allowed to remove acknowledgement assignments on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."acknowledgement_assignments" x where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."unassign_acknowledgement"(uuid) from public, anon;
grant execute on function "better_supabase"."unassign_acknowledgement"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_acknowledgement_assignments"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."acknowledgements" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1)
  );
begin
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgement assignments on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'principalType', x."principal_type", 'principalId', x."principal_id", 'dueInDays', x."due_in_days", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."principal_type", x."principal_id"), '[]'::jsonb)
    from "better_supabase"."acknowledgement_assignments" x
    where x."tenant_id" = v_tenant
      and x."subject_type" = list_acknowledgement_assignments.subject_type
      and x."subject_id" = list_acknowledgement_assignments.subject_id
  );
end;
$$;
revoke execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) from public, anon;
grant execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) to authenticated, service_role;

-- The caller acknowledges the record's current version. version_id, when
-- given, must still be the current one; signature_id names the caller's
-- completed signature on it. A second call keeps the first acknowledgement.
create or replace function "better_supabase"."acknowledge"(subject_type text, subject_id text, version_id uuid default null, signature_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant uuid;
  v_version uuid;
  v_row "better_supabase"."acknowledgements"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to acknowledge' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  select x."tenant_id" into v_tenant
    from "better_supabase"."acknowledgement_assignments" x
    join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id" and m."user_id" = v_me
    where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id
      and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
    limit 1;
  if v_tenant is null then
    raise exception 'you aren''t asked to acknowledge this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.acknowledge'), false) and true) then
    raise exception 'not allowed to acknowledge this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledge.subject_type, acknowledge.subject_id);
  if v_version is null then
    raise exception 'the record has no version to acknowledge' using errcode = '55000', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  if acknowledge.version_id is not null and acknowledge.version_id <> v_version then
    raise exception 'the record has a newer version; acknowledge that one' using errcode = '55000', hint = 'ACKNOWLEDGEMENT_VERSION_STALE';
  end if;
  if acknowledge.signature_id is not null then
    raise exception 'acknowledging with a signature needs the signatures module' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_SIGNATURE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_acknowledgement_create"(uuid, text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid, $5::uuid)', v_hook::oid::regproc)
        using v_tenant, acknowledge.subject_type, acknowledge.subject_id, v_version, v_me;
    end if;
  end;
  insert into "better_supabase"."acknowledgements" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id", "method", "signature_id")
  values (v_tenant, acknowledge.subject_type, acknowledge.subject_id, v_version, v_me, case when acknowledge.signature_id is null then 'click' else 'signature' end, acknowledge.signature_id)
  on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing
  returning * into v_row;
  if found then
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_acknowledgement_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  else
    select * into v_row from "better_supabase"."acknowledgements" x
    where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id
      and x."version_id" = v_version and x."user_id" = v_me;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id", 'method', v_row."method", 'signatureId', v_row."signature_id", 'acknowledgedAt', v_row."acknowledged_at");
end;
$$;
revoke execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) to authenticated, service_role;

-- The records the caller is asked to acknowledge in an organization, with the
-- current version, its due date and the caller's acknowledgement of it.
-- pending_only: only the ones the caller hasn't acknowledged yet.
create or replace function "better_supabase"."list_my_acknowledgements"(tenant uuid, pending_only boolean default true)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null or not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = list_my_acknowledgements.tenant and m."user_id" = v_me
  ) then
    raise exception 'not a member of this organization' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'organizationId', list_my_acknowledgements.tenant,
      'subjectType', z.subject_type,
      'subjectId', z.subject_id,
      'subjectTitle', null::text,
      'versionId', z.version_id,
      'dueOn', z.due_on,
      'overdue', k."id" is null and z.due_on is not null and z.due_on < current_date,
      'acknowledgedAt', k."acknowledged_at"
    ) order by k."id" is not null, z.due_on nulls last, z.subject_type, z.subject_id), '[]'::jsonb)
    from (
      select y.subject_type, y.subject_id, y.version_id,
        ((select vv."created_at" from "better_supabase"."versions" vv where vv."id" = y.version_id))::date + y.due_in_days as due_on
      from (
        select q.subject_type, q.subject_id, q.due_in_days,
          "better_supabase"."current_acknowledgement_version"(list_my_acknowledgements.tenant, q.subject_type, q.subject_id) as version_id
        from (
          select x."subject_type" as subject_type, x."subject_id" as subject_id, min(x."due_in_days") as due_in_days
          from "better_supabase"."acknowledgement_assignments" x
          join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id" and m."user_id" = v_me
          where x."tenant_id" = list_my_acknowledgements.tenant and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
          group by x."subject_type", x."subject_id"
        ) q
        where true
      ) y
      where y.version_id is not null
    ) z
    left join "better_supabase"."acknowledgements" k on k."subject_type" = z.subject_type and k."subject_id" = z.subject_id
      and k."version_id" = z.version_id and k."user_id" = v_me
    where not coalesce(list_my_acknowledgements.pending_only, true) or k."id" is null
  );
end;
$$;
revoke execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) to authenticated, service_role;

-- How many assigned members acknowledged the record's current version, and
-- who still has to, with their due date.
create or replace function "better_supabase"."acknowledgement_status"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1)
  );
  v_version uuid;
  v_created timestamptz;
begin
  if v_tenant is null then
    return jsonb_build_object('versionId', null, 'required', 0, 'acknowledged', 0, 'pending', '[]'::jsonb);
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgements of this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledgement_status.subject_type, acknowledgement_status.subject_id);
  select x."created_at" into v_created from "better_supabase"."versions" x where x."id" = v_version;
  return (
    select jsonb_build_object(
      'versionId', v_version,
      'required', count(*),
      'acknowledged', count(k."id"),
      'pending', coalesce(jsonb_agg(jsonb_build_object(
        'userId', c.user_id,
        'dueOn', (v_created)::date + c.due_in_days,
        'overdue', coalesce((v_created)::date + c.due_in_days < current_date, false)
      ) order by (v_created)::date + c.due_in_days nulls last, c.user_id) filter (where k."id" is null), '[]'::jsonb)
    )
    from (select m."user_id" as user_id, min(x."due_in_days") as due_in_days
      from "better_supabase"."acknowledgement_assignments" x
      join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id"
      where x."tenant_id" = v_tenant and x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id
        and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
      group by m."user_id") c
    left join "better_supabase"."acknowledgements" k on k."subject_type" = acknowledgement_status.subject_type and k."subject_id" = acknowledgement_status.subject_id
      and k."version_id" = v_version and k."user_id" = c.user_id
  );
end;
$$;
revoke execute on function "better_supabase"."acknowledgement_status"(text, text) from public, anon;
grant execute on function "better_supabase"."acknowledgement_status"(text, text) to authenticated, service_role;

-- The acknowledgements of one version of a record, default the current one.
create or replace function "better_supabase"."acknowledgements_of"(subject_type text, subject_id text, version_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1)
  );
  v_version uuid;
begin
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgements of this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := coalesce(acknowledgements_of.version_id, "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledgements_of.subject_type, acknowledgements_of.subject_id));
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'versionId', x."version_id", 'userId', x."user_id", 'method', x."method", 'signatureId', x."signature_id", 'acknowledgedAt', x."acknowledged_at") order by x."acknowledged_at"), '[]'::jsonb)
    from "better_supabase"."acknowledgements" x
    where x."tenant_id" = v_tenant
      and x."subject_type" = acknowledgements_of.subject_type
      and x."subject_id" = acknowledgements_of.subject_id
      and x."version_id" = v_version
  );
end;
$$;
revoke execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) to authenticated, service_role;

-- Reports each assigned member past the due date of a record's current
-- version once per version: an acknowledgement.reminded event and, with
-- notifications, a notification. Run it daily from a job.
create or replace function "better_supabase"."notify_due_acknowledgements"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item record;
  v_claims text;
  v_count integer := 0;
begin
  for v_item in
    select y.tenant, y.subject_type, y.subject_id, y.version_id, y.user_id,
      (vv."created_at")::date + y.due_in_days as due_on
    from (
      select q.*, "better_supabase"."current_acknowledgement_version"(q.tenant, q.subject_type, q.subject_id) as version_id
      from (
        select x."tenant_id" as tenant, x."subject_type" as subject_type, x."subject_id" as subject_id,
          m."user_id" as user_id, min(x."due_in_days") as due_in_days
        from "better_supabase"."acknowledgement_assignments" x
        join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id"
        where x."due_in_days" is not null and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
        group by x."tenant_id", x."subject_type", x."subject_id", m."user_id"
      ) q
    ) y
    join "better_supabase"."versions" vv on vv."id" = y.version_id
    where (vv."created_at")::date + y.due_in_days < current_date
      and not exists (
        select 1 from "better_supabase"."acknowledgements" k
        where k."subject_type" = y.subject_type and k."subject_id" = y.subject_id
          and k."version_id" = y.version_id and k."user_id" = y.user_id
      )
      and not exists (
        select 1 from "better_supabase"."acknowledgement_notices" nt
        where nt."subject_type" = y.subject_type and nt."subject_id" = y.subject_id
          and nt."version_id" = y.version_id and nt."user_id" = y.user_id
      )
  loop
    insert into "better_supabase"."acknowledgement_notices" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id")
    values (v_item.tenant, v_item.subject_type, v_item.subject_id, v_item.version_id, v_item.user_id)
    on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing;
    if found then
      null;
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_acknowledgements"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_due_acknowledgements"() to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgement_assignments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_select on "better_supabase"."acknowledgement_assignments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_insert on "better_supabase"."acknowledgement_assignments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_update on "better_supabase"."acknowledgement_assignments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_delete on "better_supabase"."acknowledgement_assignments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_select on "better_supabase"."acknowledgements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_insert on "better_supabase"."acknowledgements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_update on "better_supabase"."acknowledgements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_delete on "better_supabase"."acknowledgements" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.acknowledgements.api: entry points for the Data API.
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

create or replace function "api"."assign_acknowledgement"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."assign_acknowledgement"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."assign_acknowledgement"(uuid, text, text, text, text, integer) from public, anon;
grant execute on function "api"."assign_acknowledgement"(uuid, text, text, text, text, integer) to authenticated, service_role;

create or replace function "api"."unassign_acknowledgement"(assignment_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."unassign_acknowledgement"($1) $$;
revoke execute on function "api"."unassign_acknowledgement"(uuid) from public, anon;
grant execute on function "api"."unassign_acknowledgement"(uuid) to authenticated, service_role;

create or replace function "api"."list_acknowledgement_assignments"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_acknowledgement_assignments"($1, $2) $$;
revoke execute on function "api"."list_acknowledgement_assignments"(text, text) from public, anon;
grant execute on function "api"."list_acknowledgement_assignments"(text, text) to authenticated, service_role;

create or replace function "api"."acknowledge"(subject_type text, subject_id text, version_id uuid default null, signature_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."acknowledge"($1, $2, $3, $4) $$;
revoke execute on function "api"."acknowledge"(text, text, uuid, uuid) from public, anon;
grant execute on function "api"."acknowledge"(text, text, uuid, uuid) to authenticated, service_role;

create or replace function "api"."list_my_acknowledgements"(tenant uuid, pending_only boolean default true)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_my_acknowledgements"($1, $2) $$;
revoke execute on function "api"."list_my_acknowledgements"(uuid, boolean) from public, anon;
grant execute on function "api"."list_my_acknowledgements"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."acknowledgement_status"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."acknowledgement_status"($1, $2) $$;
revoke execute on function "api"."acknowledgement_status"(text, text) from public, anon;
grant execute on function "api"."acknowledgement_status"(text, text) to authenticated, service_role;

create or replace function "api"."acknowledgements_of"(subject_type text, subject_id text, version_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."acknowledgements_of"($1, $2, $3) $$;
revoke execute on function "api"."acknowledgements_of"(text, text, uuid) from public, anon;
grant execute on function "api"."acknowledgements_of"(text, text, uuid) to authenticated, service_role;

create or replace function "api"."notify_due_acknowledgements"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."notify_due_acknowledgements"() $$;
revoke execute on function "api"."notify_due_acknowledgements"() from public, anon, authenticated;
grant execute on function "api"."notify_due_acknowledgements"() to service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_147_acknowledgements.sql
-- better-supabase module: acknowledgements
-- @bsb-block-data acknowledgements
-- @bsb-hash sha256:f804dc1bd56a250af2771946adc718a33fc2dbcbbb8cd45180ca0480d6b11329
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('acknowledgements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_147_acknowledgements.sql
-- better-supabase module: acknowledgements
-- @bsb-block acknowledgements@1 managed
-- @bsb-hash sha256:f6f0184ece32df3fd8cb0142ceb6304d75935016c53c6f7176d2c60f19d0566a
-- Members confirm they read the current version of a record: assignments to a member, a team or a role, a due date per assignment, a click or a completed signature, and a reminder once a version is overdue.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgement_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgements";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgement_notices";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Acknowledgements: members confirm they read the current version of a
-- record they are assigned to, directly, through a team or through a role.

-- Who has to acknowledge a record: a member, everyone in a team, or everyone
-- holding a role, with an optional number of days to do it in.
-- better_supabase.acknowledgement_assignments is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "subject_type" text;
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "subject_id" text;
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "principal_type" text check ("principal_type" in ('user', 'team', 'role'));
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "principal_id" text check (length("principal_id") between 1 and 200);
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "due_in_days" integer check ("due_in_days" is null or ("due_in_days" >= 1 and "due_in_days" <= 365));
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "created_by" uuid default auth.uid();
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists "bsb_acknowledgement_assignments_principal_key" on "better_supabase"."acknowledgement_assignments" ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id");
create index if not exists "acknowledgement_assignments_principal_idx" on "better_supabase"."acknowledgement_assignments" ("tenant_id", "principal_type", "principal_id");
alter table "better_supabase"."acknowledgement_assignments" enable row level security;
grant select on "better_supabase"."acknowledgement_assignments" to authenticated;
grant all on "better_supabase"."acknowledgement_assignments" to service_role;
drop policy if exists bsb_acknowledgement_assignments_read on "better_supabase"."acknowledgement_assignments";
create policy bsb_acknowledgement_assignments_read on "better_supabase"."acknowledgement_assignments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- One row per member and version of a record they acknowledged.
-- better_supabase.acknowledgements is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."acknowledgements" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."acknowledgements" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."acknowledgements" add column if not exists "subject_type" text;
alter table "better_supabase"."acknowledgements" add column if not exists "subject_id" text;
alter table "better_supabase"."acknowledgements" add column if not exists "version_id" uuid references "better_supabase"."versions" ("id") on delete restrict;
alter table "better_supabase"."acknowledgements" add column if not exists "user_id" uuid;
alter table "better_supabase"."acknowledgements" add column if not exists "method" text not null default 'click' check ("method" in ('click', 'signature'));
alter table "better_supabase"."acknowledgements" add column if not exists "signature_id" uuid;
alter table "better_supabase"."acknowledgements" add column if not exists "acknowledged_at" timestamptz not null default now();
create unique index if not exists "bsb_acknowledgements_version_user_key" on "better_supabase"."acknowledgements" ("subject_type", "subject_id", "version_id", "user_id");
create index if not exists "acknowledgements_user_idx" on "better_supabase"."acknowledgements" ("tenant_id", "user_id");
create index if not exists "acknowledgements_version_idx" on "better_supabase"."acknowledgements" ("version_id", "subject_type", "subject_id");
alter table "better_supabase"."acknowledgements" enable row level security;
grant select on "better_supabase"."acknowledgements" to authenticated;
grant all on "better_supabase"."acknowledgements" to service_role;
drop policy if exists bsb_acknowledgements_read on "better_supabase"."acknowledgements";
create policy bsb_acknowledgements_read on "better_supabase"."acknowledgements"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- Which member notify_due_acknowledgements reminded about which version, so
-- each overdue version notifies a member once.
-- better_supabase.acknowledgement_notices is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."acknowledgement_notices" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."acknowledgement_notices" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."acknowledgement_notices" add column if not exists "subject_type" text;
alter table "better_supabase"."acknowledgement_notices" add column if not exists "subject_id" text;
alter table "better_supabase"."acknowledgement_notices" add column if not exists "version_id" uuid;
alter table "better_supabase"."acknowledgement_notices" add column if not exists "user_id" uuid;
alter table "better_supabase"."acknowledgement_notices" add column if not exists "notified_at" timestamptz not null default now();
create unique index if not exists "bsb_acknowledgement_notices_version_user_key" on "better_supabase"."acknowledgement_notices" ("subject_type", "subject_id", "version_id", "user_id");
alter table "better_supabase"."acknowledgement_notices" enable row level security;
grant all on "better_supabase"."acknowledgement_notices" to service_role;

-- The version of a record members acknowledge: the record's version column
-- (on.<type>.versionColumn), otherwise its latest frozen version.
create or replace function "better_supabase"."current_acknowledgement_version"(tenant uuid, subject_type text, subject_id text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (
    select x."id" from "better_supabase"."versions" x
    where x."tenant_id" = current_acknowledgement_version.tenant
      and x."subject_type" = current_acknowledgement_version.subject_type
      and x."subject_id" = current_acknowledgement_version.subject_id
      and x."frozen"
    order by x."number" desc
    limit 1
  );
end;
$$;
revoke execute on function "better_supabase"."current_acknowledgement_version"(uuid, text, text) from public, anon, authenticated;

-- Writes an assignment without checking the caller, for assign_acknowledgement
-- and for blocks that assign their own records after their own check (the
-- compliance policies). Assigning the same principal again updates its due
-- period.
create or replace function "better_supabase"."place_acknowledgement_assignment"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
  v_existed boolean;
begin
  select exists (
    select 1 from "better_supabase"."acknowledgement_assignments" x
    where x."tenant_id" = place_acknowledgement_assignment.tenant
      and x."subject_type" = place_acknowledgement_assignment.subject_type
      and x."subject_id" = place_acknowledgement_assignment.subject_id
      and x."principal_type" = place_acknowledgement_assignment.principal_type
      and x."principal_id" = place_acknowledgement_assignment.principal_id
  ) into v_existed;
  insert into "better_supabase"."acknowledgement_assignments" ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id", "due_in_days")
  values (place_acknowledgement_assignment.tenant, place_acknowledgement_assignment.subject_type, place_acknowledgement_assignment.subject_id, place_acknowledgement_assignment.principal_type, place_acknowledgement_assignment.principal_id, place_acknowledgement_assignment.due_in_days)
  on conflict ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id")
  do update set "due_in_days" = excluded."due_in_days"
  returning * into v_row;
  if not v_existed then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."place_acknowledgement_assignment"(uuid, text, text, text, text, integer) from public, anon, authenticated;

-- Removes one principal's assignment without checking the caller, for blocks
-- that manage their own records' assignments. Acknowledgements already given
-- stay.
create or replace function "better_supabase"."drop_acknowledgement_assignment"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
begin
  delete from "better_supabase"."acknowledgement_assignments" x
  where x."tenant_id" = drop_acknowledgement_assignment.tenant
    and x."subject_type" = drop_acknowledgement_assignment.subject_type
    and x."subject_id" = drop_acknowledgement_assignment.subject_id
    and x."principal_type" = drop_acknowledgement_assignment.principal_type
    and x."principal_id" = drop_acknowledgement_assignment.principal_id
  returning * into v_row;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."drop_acknowledgement_assignment"(uuid, text, text, text, text) from public, anon, authenticated;

-- Asks a member, a team or everyone holding a role to acknowledge a record,
-- within due_in_days of each new version. Assigning the same principal again
-- updates its due period.
create or replace function "better_supabase"."assign_acknowledgement"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_assignment jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'acknowledgements.manage'), false) and true)) then
    raise exception 'not allowed to assign acknowledgements on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  if assign_acknowledgement.due_in_days is not null and (assign_acknowledgement.due_in_days < 1 or assign_acknowledgement.due_in_days > 365) then
    raise exception 'due_in_days must be between 1 and 365' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_DUE_INVALID';
  end if;
  if assign_acknowledgement.principal_type = 'user' then
    if not exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = assign_acknowledgement.tenant and m."user_id"::text = assign_acknowledgement.principal_id
    ) then
      raise exception 'the user isn''t a member of this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  elsif assign_acknowledgement.principal_type = 'team' then
    raise exception 'team assignments need the teams module' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  elsif assign_acknowledgement.principal_type = 'role' then
    if not (assign_acknowledgement.principal_id = any (array['owner', 'admin', 'member', 'viewer']::text[])
      or exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = assign_acknowledgement.tenant and m."role" = assign_acknowledgement.principal_id)) then
      raise exception 'the role isn''t a role in this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  else
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_acknowledgement_assignment_create"(uuid, text, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::text)', v_hook::oid::regproc)
        using assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id, assign_acknowledgement.principal_type, assign_acknowledgement.principal_id;
    end if;
  end;
  v_assignment := "better_supabase"."place_acknowledgement_assignment"(
    assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id,
    assign_acknowledgement.principal_type, assign_acknowledgement.principal_id, assign_acknowledgement.due_in_days
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_acknowledgement_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using (v_assignment ->> 'id')::uuid;
    end if;
  end;
  return v_assignment;
end;
$$;
revoke execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) to authenticated, service_role;

-- Removes an assignment. Acknowledgements already given stay.
create or replace function "better_supabase"."unassign_acknowledgement"(assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."acknowledgement_assignments" x where x."id" = unassign_acknowledgement.assignment_id for update;
  if not found then
    raise exception 'acknowledgement assignment not found' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'acknowledgements.manage'), false) and true)) then
    raise exception 'not allowed to remove acknowledgement assignments on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."acknowledgement_assignments" x where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."unassign_acknowledgement"(uuid) from public, anon;
grant execute on function "better_supabase"."unassign_acknowledgement"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_acknowledgement_assignments"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."acknowledgements" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1)
  );
begin
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgement assignments on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'principalType', x."principal_type", 'principalId', x."principal_id", 'dueInDays', x."due_in_days", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."principal_type", x."principal_id"), '[]'::jsonb)
    from "better_supabase"."acknowledgement_assignments" x
    where x."tenant_id" = v_tenant
      and x."subject_type" = list_acknowledgement_assignments.subject_type
      and x."subject_id" = list_acknowledgement_assignments.subject_id
  );
end;
$$;
revoke execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) from public, anon;
grant execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) to authenticated, service_role;

-- The caller acknowledges the record's current version. version_id, when
-- given, must still be the current one; signature_id names the caller's
-- completed signature on it. A second call keeps the first acknowledgement.
create or replace function "better_supabase"."acknowledge"(subject_type text, subject_id text, version_id uuid default null, signature_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant uuid;
  v_version uuid;
  v_row "better_supabase"."acknowledgements"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to acknowledge' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  select x."tenant_id" into v_tenant
    from "better_supabase"."acknowledgement_assignments" x
    join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id" and m."user_id" = v_me
    where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id
      and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
    limit 1;
  if v_tenant is null then
    raise exception 'you aren''t asked to acknowledge this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.acknowledge'), false) and true) then
    raise exception 'not allowed to acknowledge this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledge.subject_type, acknowledge.subject_id);
  if v_version is null then
    raise exception 'the record has no version to acknowledge' using errcode = '55000', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  if acknowledge.version_id is not null and acknowledge.version_id <> v_version then
    raise exception 'the record has a newer version; acknowledge that one' using errcode = '55000', hint = 'ACKNOWLEDGEMENT_VERSION_STALE';
  end if;
  if acknowledge.signature_id is not null then
    raise exception 'acknowledging with a signature needs the signatures module' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_SIGNATURE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_acknowledgement_create"(uuid, text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid, $5::uuid)', v_hook::oid::regproc)
        using v_tenant, acknowledge.subject_type, acknowledge.subject_id, v_version, v_me;
    end if;
  end;
  insert into "better_supabase"."acknowledgements" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id", "method", "signature_id")
  values (v_tenant, acknowledge.subject_type, acknowledge.subject_id, v_version, v_me, case when acknowledge.signature_id is null then 'click' else 'signature' end, acknowledge.signature_id)
  on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing
  returning * into v_row;
  if found then
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_acknowledgement_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  else
    select * into v_row from "better_supabase"."acknowledgements" x
    where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id
      and x."version_id" = v_version and x."user_id" = v_me;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id", 'method', v_row."method", 'signatureId', v_row."signature_id", 'acknowledgedAt', v_row."acknowledged_at");
end;
$$;
revoke execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) to authenticated, service_role;

-- The records the caller is asked to acknowledge in an organization, with the
-- current version, its due date and the caller's acknowledgement of it.
-- pending_only: only the ones the caller hasn't acknowledged yet.
create or replace function "better_supabase"."list_my_acknowledgements"(tenant uuid, pending_only boolean default true)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null or not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = list_my_acknowledgements.tenant and m."user_id" = v_me
  ) then
    raise exception 'not a member of this organization' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'organizationId', list_my_acknowledgements.tenant,
      'subjectType', z.subject_type,
      'subjectId', z.subject_id,
      'subjectTitle', null::text,
      'versionId', z.version_id,
      'dueOn', z.due_on,
      'overdue', k."id" is null and z.due_on is not null and z.due_on < current_date,
      'acknowledgedAt', k."acknowledged_at"
    ) order by k."id" is not null, z.due_on nulls last, z.subject_type, z.subject_id), '[]'::jsonb)
    from (
      select y.subject_type, y.subject_id, y.version_id,
        ((select vv."created_at" from "better_supabase"."versions" vv where vv."id" = y.version_id))::date + y.due_in_days as due_on
      from (
        select q.subject_type, q.subject_id, q.due_in_days,
          "better_supabase"."current_acknowledgement_version"(list_my_acknowledgements.tenant, q.subject_type, q.subject_id) as version_id
        from (
          select x."subject_type" as subject_type, x."subject_id" as subject_id, min(x."due_in_days") as due_in_days
          from "better_supabase"."acknowledgement_assignments" x
          join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id" and m."user_id" = v_me
          where x."tenant_id" = list_my_acknowledgements.tenant and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
          group by x."subject_type", x."subject_id"
        ) q
        where true
      ) y
      where y.version_id is not null
    ) z
    left join "better_supabase"."acknowledgements" k on k."subject_type" = z.subject_type and k."subject_id" = z.subject_id
      and k."version_id" = z.version_id and k."user_id" = v_me
    where not coalesce(list_my_acknowledgements.pending_only, true) or k."id" is null
  );
end;
$$;
revoke execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) to authenticated, service_role;

-- How many assigned members acknowledged the record's current version, and
-- who still has to, with their due date.
create or replace function "better_supabase"."acknowledgement_status"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1)
  );
  v_version uuid;
  v_created timestamptz;
begin
  if v_tenant is null then
    return jsonb_build_object('versionId', null, 'required', 0, 'acknowledged', 0, 'pending', '[]'::jsonb);
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgements of this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledgement_status.subject_type, acknowledgement_status.subject_id);
  select x."created_at" into v_created from "better_supabase"."versions" x where x."id" = v_version;
  return (
    select jsonb_build_object(
      'versionId', v_version,
      'required', count(*),
      'acknowledged', count(k."id"),
      'pending', coalesce(jsonb_agg(jsonb_build_object(
        'userId', c.user_id,
        'dueOn', (v_created)::date + c.due_in_days,
        'overdue', coalesce((v_created)::date + c.due_in_days < current_date, false)
      ) order by (v_created)::date + c.due_in_days nulls last, c.user_id) filter (where k."id" is null), '[]'::jsonb)
    )
    from (select m."user_id" as user_id, min(x."due_in_days") as due_in_days
      from "better_supabase"."acknowledgement_assignments" x
      join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id"
      where x."tenant_id" = v_tenant and x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id
        and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
      group by m."user_id") c
    left join "better_supabase"."acknowledgements" k on k."subject_type" = acknowledgement_status.subject_type and k."subject_id" = acknowledgement_status.subject_id
      and k."version_id" = v_version and k."user_id" = c.user_id
  );
end;
$$;
revoke execute on function "better_supabase"."acknowledgement_status"(text, text) from public, anon;
grant execute on function "better_supabase"."acknowledgement_status"(text, text) to authenticated, service_role;

-- The acknowledgements of one version of a record, default the current one.
create or replace function "better_supabase"."acknowledgements_of"(subject_type text, subject_id text, version_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1)
  );
  v_version uuid;
begin
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgements of this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := coalesce(acknowledgements_of.version_id, "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledgements_of.subject_type, acknowledgements_of.subject_id));
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'versionId', x."version_id", 'userId', x."user_id", 'method', x."method", 'signatureId', x."signature_id", 'acknowledgedAt', x."acknowledged_at") order by x."acknowledged_at"), '[]'::jsonb)
    from "better_supabase"."acknowledgements" x
    where x."tenant_id" = v_tenant
      and x."subject_type" = acknowledgements_of.subject_type
      and x."subject_id" = acknowledgements_of.subject_id
      and x."version_id" = v_version
  );
end;
$$;
revoke execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) to authenticated, service_role;

-- Reports each assigned member past the due date of a record's current
-- version once per version: an acknowledgement.reminded event and, with
-- notifications, a notification. Run it daily from a job.
create or replace function "better_supabase"."notify_due_acknowledgements"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item record;
  v_claims text;
  v_count integer := 0;
begin
  for v_item in
    select y.tenant, y.subject_type, y.subject_id, y.version_id, y.user_id,
      (vv."created_at")::date + y.due_in_days as due_on
    from (
      select q.*, "better_supabase"."current_acknowledgement_version"(q.tenant, q.subject_type, q.subject_id) as version_id
      from (
        select x."tenant_id" as tenant, x."subject_type" as subject_type, x."subject_id" as subject_id,
          m."user_id" as user_id, min(x."due_in_days") as due_in_days
        from "better_supabase"."acknowledgement_assignments" x
        join "better_supabase"."memberships" m on m."organization_id" = x."tenant_id"
        where x."due_in_days" is not null and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
        group by x."tenant_id", x."subject_type", x."subject_id", m."user_id"
      ) q
    ) y
    join "better_supabase"."versions" vv on vv."id" = y.version_id
    where (vv."created_at")::date + y.due_in_days < current_date
      and not exists (
        select 1 from "better_supabase"."acknowledgements" k
        where k."subject_type" = y.subject_type and k."subject_id" = y.subject_id
          and k."version_id" = y.version_id and k."user_id" = y.user_id
      )
      and not exists (
        select 1 from "better_supabase"."acknowledgement_notices" nt
        where nt."subject_type" = y.subject_type and nt."subject_id" = y.subject_id
          and nt."version_id" = y.version_id and nt."user_id" = y.user_id
      )
  loop
    insert into "better_supabase"."acknowledgement_notices" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id")
    values (v_item.tenant, v_item.subject_type, v_item.subject_id, v_item.version_id, v_item.user_id)
    on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing;
    if found then
      null;
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_acknowledgements"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_due_acknowledgements"() to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgement_assignments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_select on "better_supabase"."acknowledgement_assignments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_insert on "better_supabase"."acknowledgement_assignments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_update on "better_supabase"."acknowledgement_assignments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_delete on "better_supabase"."acknowledgement_assignments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_select on "better_supabase"."acknowledgements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_insert on "better_supabase"."acknowledgements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_update on "better_supabase"."acknowledgements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_delete on "better_supabase"."acknowledgements" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_147_acknowledgements.sql
-- better-supabase module: acknowledgements
-- @bsb-block-data acknowledgements
-- @bsb-hash sha256:f804dc1bd56a250af2771946adc718a33fc2dbcbbb8cd45180ca0480d6b11329
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('acknowledgements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_147_acknowledgements.sql
-- better-supabase module: acknowledgements
-- @bsb-block acknowledgements@1 managed
-- @bsb-hash sha256:fe075324ec75422f175bf4608f3d30168aadd047379a93ed02c8c2559cee5e7a
-- Members confirm they read the current version of a record: assignments to a member, a team or a role, a due date per assignment, a click or a completed signature, and a reminder once a version is overdue.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgement_assignments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgement_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgements";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgement_notices";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgement_notices";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Acknowledgements: members confirm they read the current version of a
-- record they are assigned to, directly, through a team or through a role.

-- Who has to acknowledge a record: a member, everyone in a team, or everyone
-- holding a role, with an optional number of days to do it in.
create table if not exists "better_supabase"."acknowledgement_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "principal_type" text not null check ("principal_type" in ('user', 'team', 'role')),
  "principal_id" text not null check (length("principal_id") between 1 and 200),
  "due_in_days" integer check ("due_in_days" is null or ("due_in_days" >= 1 and "due_in_days" <= 365)),
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("org_id", "subject_type", "subject_id", "principal_type", "principal_id")
);
create index if not exists "acknowledgement_assignments_principal_idx" on "better_supabase"."acknowledgement_assignments" ("org_id", "principal_type", "principal_id");
alter table "better_supabase"."acknowledgement_assignments" enable row level security;
revoke all on "better_supabase"."acknowledgement_assignments" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgement_assignments" to authenticated;
grant all on "better_supabase"."acknowledgement_assignments" to service_role;
drop policy if exists acknowledgement_assignments_read on "better_supabase"."acknowledgement_assignments";
create policy acknowledgement_assignments_read on "better_supabase"."acknowledgement_assignments"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- One row per member and version of a record they acknowledged.
create table if not exists "better_supabase"."acknowledgements" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null references "better_supabase"."versions" ("id") on delete restrict,
  "user_id" uuid not null,
  "method" text not null default 'click' check ("method" in ('click', 'signature')),
  "signature_id" uuid,
  "acknowledged_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "version_id", "user_id")
);
create index if not exists "acknowledgements_user_idx" on "better_supabase"."acknowledgements" ("org_id", "user_id");
create index if not exists "acknowledgements_version_idx" on "better_supabase"."acknowledgements" ("version_id", "subject_type", "subject_id");
alter table "better_supabase"."acknowledgements" enable row level security;
revoke all on "better_supabase"."acknowledgements" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgements" to authenticated;
grant all on "better_supabase"."acknowledgements" to service_role;
drop policy if exists acknowledgements_read on "better_supabase"."acknowledgements";
create policy acknowledgements_read on "better_supabase"."acknowledgements"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- Which member notify_due_acknowledgements reminded about which version, so
-- each overdue version notifies a member once.
create table if not exists "better_supabase"."acknowledgement_notices" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null,
  "user_id" uuid not null,
  "notified_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "version_id", "user_id")
);
alter table "better_supabase"."acknowledgement_notices" enable row level security;
revoke all on "better_supabase"."acknowledgement_notices" from public, anon, authenticated;
grant all on "better_supabase"."acknowledgement_notices" to service_role;

-- The version of a record members acknowledge: the record's version column
-- (on.<type>.versionColumn), otherwise its latest frozen version.
create or replace function "better_supabase"."current_acknowledgement_version"(tenant uuid, subject_type text, subject_id text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (
    select x."id" from "better_supabase"."versions" x
    where x."org_id" = current_acknowledgement_version.tenant
      and x."subject_type" = current_acknowledgement_version.subject_type
      and x."subject_id" = current_acknowledgement_version.subject_id
      and x."frozen"
    order by x."number" desc
    limit 1
  );
end;
$$;
revoke execute on function "better_supabase"."current_acknowledgement_version"(uuid, text, text) from public, anon, authenticated;

-- Writes an assignment without checking the caller, for assign_acknowledgement
-- and for blocks that assign their own records after their own check (the
-- compliance policies). Assigning the same principal again updates its due
-- period.
create or replace function "better_supabase"."place_acknowledgement_assignment"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
  v_existed boolean;
begin
  select exists (
    select 1 from "better_supabase"."acknowledgement_assignments" x
    where x."org_id" = place_acknowledgement_assignment.tenant
      and x."subject_type" = place_acknowledgement_assignment.subject_type
      and x."subject_id" = place_acknowledgement_assignment.subject_id
      and x."principal_type" = place_acknowledgement_assignment.principal_type
      and x."principal_id" = place_acknowledgement_assignment.principal_id
  ) into v_existed;
  insert into "better_supabase"."acknowledgement_assignments" ("org_id", "subject_type", "subject_id", "principal_type", "principal_id", "due_in_days")
  values (place_acknowledgement_assignment.tenant, place_acknowledgement_assignment.subject_type, place_acknowledgement_assignment.subject_id, place_acknowledgement_assignment.principal_type, place_acknowledgement_assignment.principal_id, place_acknowledgement_assignment.due_in_days)
  on conflict ("org_id", "subject_type", "subject_id", "principal_type", "principal_id")
  do update set "due_in_days" = excluded."due_in_days"
  returning * into v_row;
  if not v_existed then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."place_acknowledgement_assignment"(uuid, text, text, text, text, integer) from public, anon, authenticated;

-- Removes one principal's assignment without checking the caller, for blocks
-- that manage their own records' assignments. Acknowledgements already given
-- stay.
create or replace function "better_supabase"."drop_acknowledgement_assignment"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
begin
  delete from "better_supabase"."acknowledgement_assignments" x
  where x."org_id" = drop_acknowledgement_assignment.tenant
    and x."subject_type" = drop_acknowledgement_assignment.subject_type
    and x."subject_id" = drop_acknowledgement_assignment.subject_id
    and x."principal_type" = drop_acknowledgement_assignment.principal_type
    and x."principal_id" = drop_acknowledgement_assignment.principal_id
  returning * into v_row;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."drop_acknowledgement_assignment"(uuid, text, text, text, text) from public, anon, authenticated;

-- Asks a member, a team or everyone holding a role to acknowledge a record,
-- within due_in_days of each new version. Assigning the same principal again
-- updates its due period.
create or replace function "better_supabase"."assign_acknowledgement"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_assignment jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'acknowledgements.manage'), false) and true)) then
    raise exception 'not allowed to assign acknowledgements on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  if assign_acknowledgement.due_in_days is not null and (assign_acknowledgement.due_in_days < 1 or assign_acknowledgement.due_in_days > 365) then
    raise exception 'due_in_days must be between 1 and 365' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_DUE_INVALID';
  end if;
  if assign_acknowledgement.principal_type = 'user' then
    if not exists (
      select 1 from "better_supabase"."memberships" m
      where m."org_id" = assign_acknowledgement.tenant and m."user_id"::text = assign_acknowledgement.principal_id
    ) then
      raise exception 'the user isn''t a member of this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  elsif assign_acknowledgement.principal_type = 'team' then
    raise exception 'team assignments need the teams module' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  elsif assign_acknowledgement.principal_type = 'role' then
    if not (assign_acknowledgement.principal_id = any (array['owner', 'admin', 'member', 'viewer']::text[])
      or exists (select 1 from "better_supabase"."memberships" m where m."org_id" = assign_acknowledgement.tenant and m."role" = assign_acknowledgement.principal_id)) then
      raise exception 'the role isn''t a role in this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  else
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_acknowledgement_assignment_create"(uuid, text, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::text)', v_hook::oid::regproc)
        using assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id, assign_acknowledgement.principal_type, assign_acknowledgement.principal_id;
    end if;
  end;
  v_assignment := "better_supabase"."place_acknowledgement_assignment"(
    assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id,
    assign_acknowledgement.principal_type, assign_acknowledgement.principal_id, assign_acknowledgement.due_in_days
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_acknowledgement_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using (v_assignment ->> 'id')::uuid;
    end if;
  end;
  return v_assignment;
end;
$$;
revoke execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) to authenticated, service_role;

-- Removes an assignment. Acknowledgements already given stay.
create or replace function "better_supabase"."unassign_acknowledgement"(assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."acknowledgement_assignments" x where x."id" = unassign_acknowledgement.assignment_id for update;
  if not found then
    raise exception 'acknowledgement assignment not found' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_row."org_id", 'acknowledgements.manage'), false) and true)) then
    raise exception 'not allowed to remove acknowledgement assignments on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."acknowledgement_assignments" x where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."unassign_acknowledgement"(uuid) from public, anon;
grant execute on function "better_supabase"."unassign_acknowledgement"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_acknowledgement_assignments"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := coalesce(
    (select x."org_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1),
    (select x."org_id" from "better_supabase"."acknowledgements" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1),
    (select x."org_id" from "better_supabase"."versions" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1)
  );
begin
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgement assignments on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'principalType', x."principal_type", 'principalId', x."principal_id", 'dueInDays', x."due_in_days", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."principal_type", x."principal_id"), '[]'::jsonb)
    from "better_supabase"."acknowledgement_assignments" x
    where x."org_id" = v_tenant
      and x."subject_type" = list_acknowledgement_assignments.subject_type
      and x."subject_id" = list_acknowledgement_assignments.subject_id
  );
end;
$$;
revoke execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) from public, anon;
grant execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) to authenticated, service_role;

-- The caller acknowledges the record's current version. version_id, when
-- given, must still be the current one; signature_id names the caller's
-- completed signature on it. A second call keeps the first acknowledgement.
create or replace function "better_supabase"."acknowledge"(subject_type text, subject_id text, version_id uuid default null, signature_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant uuid;
  v_version uuid;
  v_row "better_supabase"."acknowledgements"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to acknowledge' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  select x."org_id" into v_tenant
    from "better_supabase"."acknowledgement_assignments" x
    join "better_supabase"."memberships" m on m."org_id" = x."org_id" and m."user_id" = v_me
    where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id
      and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
    limit 1;
  if v_tenant is null then
    raise exception 'you aren''t asked to acknowledge this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.acknowledge'), false) and true) then
    raise exception 'not allowed to acknowledge this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledge.subject_type, acknowledge.subject_id);
  if v_version is null then
    raise exception 'the record has no version to acknowledge' using errcode = '55000', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  if acknowledge.version_id is not null and acknowledge.version_id <> v_version then
    raise exception 'the record has a newer version; acknowledge that one' using errcode = '55000', hint = 'ACKNOWLEDGEMENT_VERSION_STALE';
  end if;
  if acknowledge.signature_id is not null then
    raise exception 'acknowledging with a signature needs the signatures module' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_SIGNATURE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_acknowledgement_create"(uuid, text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid, $5::uuid)', v_hook::oid::regproc)
        using v_tenant, acknowledge.subject_type, acknowledge.subject_id, v_version, v_me;
    end if;
  end;
  insert into "better_supabase"."acknowledgements" ("org_id", "subject_type", "subject_id", "version_id", "user_id", "method", "signature_id")
  values (v_tenant, acknowledge.subject_type, acknowledge.subject_id, v_version, v_me, case when acknowledge.signature_id is null then 'click' else 'signature' end, acknowledge.signature_id)
  on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing
  returning * into v_row;
  if found then
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_acknowledgement_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  else
    select * into v_row from "better_supabase"."acknowledgements" x
    where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id
      and x."version_id" = v_version and x."user_id" = v_me;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id", 'method', v_row."method", 'signatureId', v_row."signature_id", 'acknowledgedAt', v_row."acknowledged_at");
end;
$$;
revoke execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) to authenticated, service_role;

-- The records the caller is asked to acknowledge in an organization, with the
-- current version, its due date and the caller's acknowledgement of it.
-- pending_only: only the ones the caller hasn't acknowledged yet.
create or replace function "better_supabase"."list_my_acknowledgements"(tenant uuid, pending_only boolean default true)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null or not exists (
    select 1 from "better_supabase"."memberships" m where m."org_id" = list_my_acknowledgements.tenant and m."user_id" = v_me
  ) then
    raise exception 'not a member of this organization' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'organizationId', list_my_acknowledgements.tenant,
      'subjectType', z.subject_type,
      'subjectId', z.subject_id,
      'subjectTitle', null::text,
      'versionId', z.version_id,
      'dueOn', z.due_on,
      'overdue', k."id" is null and z.due_on is not null and z.due_on < current_date,
      'acknowledgedAt', k."acknowledged_at"
    ) order by k."id" is not null, z.due_on nulls last, z.subject_type, z.subject_id), '[]'::jsonb)
    from (
      select y.subject_type, y.subject_id, y.version_id,
        ((select vv."created_at" from "better_supabase"."versions" vv where vv."id" = y.version_id))::date + y.due_in_days as due_on
      from (
        select q.subject_type, q.subject_id, q.due_in_days,
          "better_supabase"."current_acknowledgement_version"(list_my_acknowledgements.tenant, q.subject_type, q.subject_id) as version_id
        from (
          select x."subject_type" as subject_type, x."subject_id" as subject_id, min(x."due_in_days") as due_in_days
          from "better_supabase"."acknowledgement_assignments" x
          join "better_supabase"."memberships" m on m."org_id" = x."org_id" and m."user_id" = v_me
          where x."org_id" = list_my_acknowledgements.tenant and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
          group by x."subject_type", x."subject_id"
        ) q
        where true
      ) y
      where y.version_id is not null
    ) z
    left join "better_supabase"."acknowledgements" k on k."subject_type" = z.subject_type and k."subject_id" = z.subject_id
      and k."version_id" = z.version_id and k."user_id" = v_me
    where not coalesce(list_my_acknowledgements.pending_only, true) or k."id" is null
  );
end;
$$;
revoke execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) to authenticated, service_role;

-- How many assigned members acknowledged the record's current version, and
-- who still has to, with their due date.
create or replace function "better_supabase"."acknowledgement_status"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := coalesce(
    (select x."org_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1),
    (select x."org_id" from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1),
    (select x."org_id" from "better_supabase"."versions" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1)
  );
  v_version uuid;
  v_created timestamptz;
begin
  if v_tenant is null then
    return jsonb_build_object('versionId', null, 'required', 0, 'acknowledged', 0, 'pending', '[]'::jsonb);
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgements of this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledgement_status.subject_type, acknowledgement_status.subject_id);
  select x."created_at" into v_created from "better_supabase"."versions" x where x."id" = v_version;
  return (
    select jsonb_build_object(
      'versionId', v_version,
      'required', count(*),
      'acknowledged', count(k."id"),
      'pending', coalesce(jsonb_agg(jsonb_build_object(
        'userId', c.user_id,
        'dueOn', (v_created)::date + c.due_in_days,
        'overdue', coalesce((v_created)::date + c.due_in_days < current_date, false)
      ) order by (v_created)::date + c.due_in_days nulls last, c.user_id) filter (where k."id" is null), '[]'::jsonb)
    )
    from (select m."user_id" as user_id, min(x."due_in_days") as due_in_days
      from "better_supabase"."acknowledgement_assignments" x
      join "better_supabase"."memberships" m on m."org_id" = x."org_id"
      where x."org_id" = v_tenant and x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id
        and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
      group by m."user_id") c
    left join "better_supabase"."acknowledgements" k on k."subject_type" = acknowledgement_status.subject_type and k."subject_id" = acknowledgement_status.subject_id
      and k."version_id" = v_version and k."user_id" = c.user_id
  );
end;
$$;
revoke execute on function "better_supabase"."acknowledgement_status"(text, text) from public, anon;
grant execute on function "better_supabase"."acknowledgement_status"(text, text) to authenticated, service_role;

-- The acknowledgements of one version of a record, default the current one.
create or replace function "better_supabase"."acknowledgements_of"(subject_type text, subject_id text, version_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid := coalesce(
    (select x."org_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1),
    (select x."org_id" from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1),
    (select x."org_id" from "better_supabase"."versions" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1)
  );
  v_version uuid;
begin
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and true)) then
    raise exception 'not allowed to read acknowledgements of this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := coalesce(acknowledgements_of.version_id, "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledgements_of.subject_type, acknowledgements_of.subject_id));
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'versionId', x."version_id", 'userId', x."user_id", 'method', x."method", 'signatureId', x."signature_id", 'acknowledgedAt', x."acknowledged_at") order by x."acknowledged_at"), '[]'::jsonb)
    from "better_supabase"."acknowledgements" x
    where x."org_id" = v_tenant
      and x."subject_type" = acknowledgements_of.subject_type
      and x."subject_id" = acknowledgements_of.subject_id
      and x."version_id" = v_version
  );
end;
$$;
revoke execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) to authenticated, service_role;

-- Reports each assigned member past the due date of a record's current
-- version once per version: an acknowledgement.reminded event and, with
-- notifications, a notification. Run it daily from a job.
create or replace function "better_supabase"."notify_due_acknowledgements"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item record;
  v_claims text;
  v_count integer := 0;
begin
  for v_item in
    select y.tenant, y.subject_type, y.subject_id, y.version_id, y.user_id,
      (vv."created_at")::date + y.due_in_days as due_on
    from (
      select q.*, "better_supabase"."current_acknowledgement_version"(q.tenant, q.subject_type, q.subject_id) as version_id
      from (
        select x."org_id" as tenant, x."subject_type" as subject_type, x."subject_id" as subject_id,
          m."user_id" as user_id, min(x."due_in_days") as due_in_days
        from "better_supabase"."acknowledgement_assignments" x
        join "better_supabase"."memberships" m on m."org_id" = x."org_id"
        where x."due_in_days" is not null and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = m."role"))
        group by x."org_id", x."subject_type", x."subject_id", m."user_id"
      ) q
    ) y
    join "better_supabase"."versions" vv on vv."id" = y.version_id
    where (vv."created_at")::date + y.due_in_days < current_date
      and not exists (
        select 1 from "better_supabase"."acknowledgements" k
        where k."subject_type" = y.subject_type and k."subject_id" = y.subject_id
          and k."version_id" = y.version_id and k."user_id" = y.user_id
      )
      and not exists (
        select 1 from "better_supabase"."acknowledgement_notices" nt
        where nt."subject_type" = y.subject_type and nt."subject_id" = y.subject_id
          and nt."version_id" = y.version_id and nt."user_id" = y.user_id
      )
  loop
    insert into "better_supabase"."acknowledgement_notices" ("org_id", "subject_type", "subject_id", "version_id", "user_id")
    values (v_item.tenant, v_item.subject_type, v_item.subject_id, v_item.version_id, v_item.user_id)
    on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing;
    if found then
      null;
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_acknowledgements"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_due_acknowledgements"() to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgement_assignments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_select on "better_supabase"."acknowledgement_assignments" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_insert on "better_supabase"."acknowledgement_assignments" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_update on "better_supabase"."acknowledgement_assignments" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgement_assignments";
create policy bsb_tenant_scope_delete on "better_supabase"."acknowledgement_assignments" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."acknowledgements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_select on "better_supabase"."acknowledgements" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_insert on "better_supabase"."acknowledgements" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_update on "better_supabase"."acknowledgements" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."acknowledgements";
create policy bsb_tenant_scope_delete on "better_supabase"."acknowledgements" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_147_acknowledgements.sql
-- better-supabase module: acknowledgements
-- @bsb-block-data acknowledgements
-- @bsb-hash sha256:f804dc1bd56a250af2771946adc718a33fc2dbcbbb8cd45180ca0480d6b11329
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('acknowledgements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
