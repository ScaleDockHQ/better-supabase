-- ==== alone: schema supabase/schemas/900_better_supabase_147_acknowledgements.sql
-- better-supabase module: acknowledgements
-- @bsb-block acknowledgements@1 managed
-- @bsb-hash sha256:0f4f299dc2a6318445fac0b7be072107dcc9c1ab727accae833c5d14a4e81ff9
-- Which member acknowledged which version of a record, with assignments to users, teams and roles, a due date, an effectiveness status and overdue notifications.
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
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Acknowledgements: which member read which version of a record, and the
-- assignments that make a version due.

create table if not exists "better_supabase"."acknowledgement_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "principal_type" text not null check ("principal_type" in ('user', 'team', 'role')),
  "principal_id" text not null,
  "due_in_days" integer check ("due_in_days" between 1 and 365),
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id")
);
create index if not exists acknowledgement_assignments_principal_idx on "better_supabase"."acknowledgement_assignments" ("tenant_id", "principal_type", "principal_id");
alter table "better_supabase"."acknowledgement_assignments" enable row level security;
revoke all on "better_supabase"."acknowledgement_assignments" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgement_assignments" to authenticated;
grant all on "better_supabase"."acknowledgement_assignments" to service_role;
create policy acknowledgement_assignments_read on better_supabase.acknowledgement_assignments
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

create table if not exists "better_supabase"."acknowledgements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null,
  "user_id" uuid not null,
  "method" text not null default 'click' check ("method" in ('click', 'signature')),
  "signature_id" uuid,
  "acknowledged_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "version_id", "user_id")
);
create index if not exists acknowledgements_user_idx on "better_supabase"."acknowledgements" ("tenant_id", "user_id");
create index if not exists acknowledgements_subject_idx on "better_supabase"."acknowledgements" ("subject_type", "subject_id", "version_id");
alter table "better_supabase"."acknowledgements" enable row level security;
revoke all on "better_supabase"."acknowledgements" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgements" to authenticated;
grant all on "better_supabase"."acknowledgements" to service_role;
create policy acknowledgements_read on better_supabase.acknowledgements
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- The current frozen version of a record: the newest frozen version in versions.
create or replace function "better_supabase"."current_acknowledgement_version"(subject_type text, subject_id text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select v."id"
  from "better_supabase"."versions" v
  where v."subject_type" = $1 and v."subject_id" = $2 and v."frozen"
  order by v."number" desc
  limit 1
$$;
revoke execute on function "better_supabase"."current_acknowledgement_version"(text, text) from public, anon, authenticated;

-- Assigns a record's current version to a user, a team or a role.
create or replace function "better_supabase"."assign_acknowledgement"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
  v_version uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'acknowledgements.manage'), false)) then
    raise exception 'not allowed to assign acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  if principal_type not in ('user', 'team', 'role') then
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  if principal_type = 'user' and not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = assign_acknowledgement.tenant and m."user_id" = assign_acknowledgement.principal_id::uuid
  ) then
    raise exception 'the user must be a member of the organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  
  if principal_type = 'role' and not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = assign_acknowledgement.tenant and m."role"::text = assign_acknowledgement.principal_id
  ) then
    raise exception 'the role must exist in the organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(subject_type, subject_id);
  if v_version is null then
    raise exception 'the record has no frozen version to acknowledge' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  insert into "better_supabase"."acknowledgement_assignments" ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id", "due_in_days")
  values (assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id, assign_acknowledgement.principal_type, assign_acknowledgement.principal_id, assign_acknowledgement.due_in_days)
  on conflict ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id") do update
    set "due_in_days" = excluded."due_in_days"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) to authenticated, service_role;

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
  select * into v_row from "better_supabase"."acknowledgement_assignments" x where x."id" = unassign_acknowledgement.assignment_id;
  if not found then
    raise exception 'assignment not found' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'acknowledgements.manage'), false)) then
    raise exception 'not allowed to manage acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
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
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'principalType', x."principal_type", 'principalId', x."principal_id", 'dueInDays', x."due_in_days", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."acknowledgement_assignments" x
  where x."subject_type" = $1 and x."subject_id" = $2
    and x."tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read'))
$$;
revoke execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) from public, anon;
grant execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) to authenticated, service_role;

-- A member acknowledges the current version of a record they are assigned.
create or replace function "better_supabase"."acknowledge"(subject_type text, subject_id text, version_id uuid default null, signature_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."acknowledgements"%rowtype;
  v_tenant uuid;
  v_version uuid;
  v_current uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select m."organization_id" into v_tenant from "better_supabase"."memberships" m where m."user_id" = auth.uid() limit 1;
  if v_tenant is null or not coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.acknowledge'), false) then
    raise exception 'not allowed to acknowledge' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_current := "better_supabase"."current_acknowledgement_version"(subject_type, subject_id);
  if v_current is null then
    raise exception 'the record has no frozen version to acknowledge' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  if version_id is not null and version_id <> v_current then
    raise exception 'the record has a newer version' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_VERSION_STALE';
  end if;
  if not exists (select 1 from "better_supabase"."acknowledgement_assignments" x where x."tenant_id" = v_tenant and x."subject_type" = subject_type and x."subject_id" = subject_id and (
      (x."principal_type" = 'user' and x."principal_id" = auth.uid()::text)
      or (x."principal_type" = 'role' and x."principal_id" = (select m."role" from "better_supabase"."memberships" m where m."organization_id" = v_tenant and m."user_id" = auth.uid())::text)
      
    )) then
    raise exception 'you are not assigned this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  
  insert into "better_supabase"."acknowledgements" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id", "method", "signature_id")
  values (v_tenant, acknowledge.subject_type, acknowledge.subject_id, coalesce(acknowledge.version_id, v_current), auth.uid(), case when acknowledge.signature_id is null then 'click' else 'signature' end, acknowledge.signature_id)
  on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id and x."version_id" = coalesce(acknowledge.version_id, v_current) and x."user_id" = auth.uid();
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id", 'method', v_row."method", 'signatureId', v_row."signature_id", 'acknowledgedAt', v_row."acknowledged_at");
end;
$$;
revoke execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_my_acknowledgements"(tenant uuid, pending_only boolean default true)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectType', x."subject_type",
    'subjectId', x."subject_id",
    'assignmentId', x."id",
    'versionId', "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id"),
    'dueOn', case when x."due_in_days" is null then null else ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days")::text end,
    'overdue', case when x."due_in_days" is not null and ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days") < current_date then true else false end,
    'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = x."subject_type" and ack."subject_id" = x."subject_id" and ack."version_id" = "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id") and ack."user_id" = auth.uid())
  ) order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."acknowledgement_assignments" x
  where x."tenant_id" = list_my_acknowledgements.tenant
    and exists (select 1 from "better_supabase"."acknowledgement_assignments" x where x."tenant_id" = x."tenant_id" and x."subject_type" = x."subject_type" and x."subject_id" = x."subject_id" and (
      (x."principal_type" = 'user' and x."principal_id" = auth.uid()::text)
      or (x."principal_type" = 'role' and x."principal_id" = (select m."role" from "better_supabase"."memberships" m where m."organization_id" = x."tenant_id" and m."user_id" = auth.uid())::text)
      
    ))
    and (not list_my_acknowledgements.pending_only or not exists (
      select 1 from "better_supabase"."acknowledgements" ack where ack."subject_type" = x."subject_type" and ack."subject_id" = x."subject_id" and ack."version_id" = "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id") and ack."user_id" = auth.uid()
    ))
$$;
revoke execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."acknowledgement_status"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_version uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1;
  if v_tenant is null then
    raise exception 'the record has no assignment' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  if not coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) then
    raise exception 'not allowed to read acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(subject_type, subject_id);
  return jsonb_build_object(
    'versionId', v_version,
    'required', (select count(*) from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id),
    'acknowledged', (select count(*) from "better_supabase"."acknowledgements" ack where ack."subject_type" = acknowledgement_status.subject_type and ack."subject_id" = acknowledgement_status.subject_id and ack."version_id" = v_version),
    'pending', coalesce((select jsonb_agg(jsonb_build_object('userId', m."user_id", 'dueOn', case when x."due_in_days" is null then null else ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = acknowledgement_status.subject_type and v."subject_id" = acknowledgement_status.subject_id and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days")::text end, 'overdue', case when x."due_in_days" is not null and ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = acknowledgement_status.subject_type and v."subject_id" = acknowledgement_status.subject_id and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days") < current_date then true else false end)) from "better_supabase"."memberships" m join "better_supabase"."acknowledgement_assignments" x on x."tenant_id" = m."organization_id" and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text) or (x."principal_type" = 'role' and x."principal_id" = m."role"::text)) where m."organization_id" = v_tenant and x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id and not exists (select 1 from "better_supabase"."acknowledgements" ack where ack."subject_type" = acknowledgement_status.subject_type and ack."subject_id" = acknowledgement_status.subject_id and ack."version_id" = v_version and ack."user_id" = m."user_id")), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."acknowledgement_status"(text, text) from public, anon;
grant execute on function "better_supabase"."acknowledgement_status"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."acknowledgements_of"(subject_type text, subject_id text, version_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', x."user_id", 'versionId', x."version_id", 'method', x."method", 'signatureId', x."signature_id", 'acknowledgedAt', x."acknowledged_at") order by x."acknowledged_at" desc), '[]'::jsonb)
  from "better_supabase"."acknowledgements" x
  where x."subject_type" = $1 and x."subject_id" = $2
    and ($3 is null or x."version_id" = $3)
    and x."tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read'))
$$;
revoke execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) to authenticated, service_role;

create or replace function "better_supabase"."notify_due_acknowledgements"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
  v_due date;
  v_version uuid;
begin
  for v_row in
    select x.*, (select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date as version_on,
      "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id") as version_id
    from "better_supabase"."acknowledgement_assignments" x
    where x."due_in_days" is not null
  loop
    v_due := v_row.version_on + v_row."due_in_days";
    v_version := v_row.version_id;
    if v_version is not null and v_due <= current_date then
      null;
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
-- @bsb-hash sha256:f9ba92877b730ef36732ad0a2b635977aec2715edf3d6661e72b90486e1bfbf5
-- Which member acknowledged which version of a record, with assignments to users, teams and roles, a due date, an effectiveness status and overdue notifications.
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
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Acknowledgements: which member read which version of a record, and the
-- assignments that make a version due.

create table if not exists "better_supabase"."acknowledgement_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "principal_type" text not null check ("principal_type" in ('user', 'team', 'role')),
  "principal_id" text not null,
  "due_in_days" integer check ("due_in_days" between 1 and 365),
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id")
);
create index if not exists acknowledgement_assignments_principal_idx on "better_supabase"."acknowledgement_assignments" ("tenant_id", "principal_type", "principal_id");
alter table "better_supabase"."acknowledgement_assignments" enable row level security;
revoke all on "better_supabase"."acknowledgement_assignments" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgement_assignments" to authenticated;
grant all on "better_supabase"."acknowledgement_assignments" to service_role;
create policy acknowledgement_assignments_read on better_supabase.acknowledgement_assignments
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

create table if not exists "better_supabase"."acknowledgements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null,
  "user_id" uuid not null,
  "method" text not null default 'click' check ("method" in ('click', 'signature')),
  "signature_id" uuid,
  "acknowledged_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "version_id", "user_id")
);
create index if not exists acknowledgements_user_idx on "better_supabase"."acknowledgements" ("tenant_id", "user_id");
create index if not exists acknowledgements_subject_idx on "better_supabase"."acknowledgements" ("subject_type", "subject_id", "version_id");
alter table "better_supabase"."acknowledgements" enable row level security;
revoke all on "better_supabase"."acknowledgements" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgements" to authenticated;
grant all on "better_supabase"."acknowledgements" to service_role;
create policy acknowledgements_read on better_supabase.acknowledgements
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- The current frozen version of a record: the newest frozen version in versions.
create or replace function "better_supabase"."current_acknowledgement_version"(subject_type text, subject_id text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select v."id"
  from "better_supabase"."versions" v
  where v."subject_type" = $1 and v."subject_id" = $2 and v."frozen"
  order by v."number" desc
  limit 1
$$;
revoke execute on function "better_supabase"."current_acknowledgement_version"(text, text) from public, anon, authenticated;

-- Assigns a record's current version to a user, a team or a role.
create or replace function "better_supabase"."assign_acknowledgement"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
  v_version uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'acknowledgements.manage'), false)) then
    raise exception 'not allowed to assign acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  if principal_type not in ('user', 'team', 'role') then
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  if principal_type = 'user' and not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = assign_acknowledgement.tenant and m."user_id" = assign_acknowledgement.principal_id::uuid
  ) then
    raise exception 'the user must be a member of the organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  if principal_type = 'team' and not exists (
    select 1 from "better_supabase"."teams" t where t."tenant_id" = assign_acknowledgement.tenant and t."id"::text = assign_acknowledgement.principal_id
  ) then
    raise exception 'the team must exist in the organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  if principal_type = 'role' and not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = assign_acknowledgement.tenant and m."role"::text = assign_acknowledgement.principal_id
  ) then
    raise exception 'the role must exist in the organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(subject_type, subject_id);
  if v_version is null then
    raise exception 'the record has no frozen version to acknowledge' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  insert into "better_supabase"."acknowledgement_assignments" ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id", "due_in_days")
  values (assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id, assign_acknowledgement.principal_type, assign_acknowledgement.principal_id, assign_acknowledgement.due_in_days)
  on conflict ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id") do update
    set "due_in_days" = excluded."due_in_days"
  returning * into v_row;
  perform "better_supabase".emit_event('acknowledgement_assignment.created', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'assignmentId', v_row."id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueOn', case when v_row."due_in_days" is null then null else ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = v_row."subject_type" and v."subject_id" = v_row."subject_id" and v."frozen" order by v."number" desc limit 1)::date + v_row."due_in_days")::text end), 'acknowledgement-assignments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/acknowledgements');
  perform better_supabase.audit_event(
    event_type => 'acknowledgement_assignment.created',
    category => 'data',
    target_type => 'acknowledgement_assignment',
    record_id => v_row."id"::text,
    summary => 'assigned acknowledgement',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'assignmentId', v_row."id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueOn', case when v_row."due_in_days" is null then null else ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = v_row."subject_type" and v."subject_id" = v_row."subject_id" and v."frozen" order by v."number" desc limit 1)::date + v_row."due_in_days")::text end)
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) to authenticated, service_role;

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
  select * into v_row from "better_supabase"."acknowledgement_assignments" x where x."id" = unassign_acknowledgement.assignment_id;
  if not found then
    raise exception 'assignment not found' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'acknowledgements.manage'), false)) then
    raise exception 'not allowed to manage acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."acknowledgement_assignments" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('acknowledgement_assignment.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'assignmentId', v_row."id"), 'acknowledgement-assignments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/acknowledgements');
  perform better_supabase.audit_event(
    event_type => 'acknowledgement_assignment.deleted',
    category => 'data',
    target_type => 'acknowledgement_assignment',
    record_id => v_row."id"::text,
    summary => 'removed acknowledgement assignment',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'assignmentId', v_row."id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."unassign_acknowledgement"(uuid) from public, anon;
grant execute on function "better_supabase"."unassign_acknowledgement"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_acknowledgement_assignments"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'principalType', x."principal_type", 'principalId', x."principal_id", 'dueInDays', x."due_in_days", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."acknowledgement_assignments" x
  where x."subject_type" = $1 and x."subject_id" = $2
    and x."tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read'))
$$;
revoke execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) from public, anon;
grant execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) to authenticated, service_role;

-- A member acknowledges the current version of a record they are assigned.
create or replace function "better_supabase"."acknowledge"(subject_type text, subject_id text, version_id uuid default null, signature_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."acknowledgements"%rowtype;
  v_tenant uuid;
  v_version uuid;
  v_current uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select m."organization_id" into v_tenant from "better_supabase"."memberships" m where m."user_id" = auth.uid() limit 1;
  if v_tenant is null or not coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.acknowledge'), false) then
    raise exception 'not allowed to acknowledge' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_current := "better_supabase"."current_acknowledgement_version"(subject_type, subject_id);
  if v_current is null then
    raise exception 'the record has no frozen version to acknowledge' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  if version_id is not null and version_id <> v_current then
    raise exception 'the record has a newer version' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_VERSION_STALE';
  end if;
  if not exists (select 1 from "better_supabase"."acknowledgement_assignments" x where x."tenant_id" = v_tenant and x."subject_type" = subject_type and x."subject_id" = subject_id and (
      (x."principal_type" = 'user' and x."principal_id" = auth.uid()::text)
      or (x."principal_type" = 'role' and x."principal_id" = (select m."role" from "better_supabase"."memberships" m where m."organization_id" = v_tenant and m."user_id" = auth.uid())::text)
      or (x."principal_type" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = x."principal_id" and tm."user_id" = auth.uid()))
    )) then
    raise exception 'you are not assigned this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  if signature_id is not null and not exists (
    select 1 from "better_supabase"."signature_requests" s
    where s."id" = acknowledge.signature_id
      and s."status" = 'completed'
      and s."subject_type" = acknowledge.subject_type
      and s."subject_id" = acknowledge.subject_id
  ) then
    raise exception 'the signature is not completed for this record' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_SIGNATURE_INVALID';
  end if;
  insert into "better_supabase"."acknowledgements" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id", "method", "signature_id")
  values (v_tenant, acknowledge.subject_type, acknowledge.subject_id, coalesce(acknowledge.version_id, v_current), auth.uid(), case when acknowledge.signature_id is null then 'click' else 'signature' end, acknowledge.signature_id)
  on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id and x."version_id" = coalesce(acknowledge.version_id, v_current) and x."user_id" = auth.uid();
  else
    perform "better_supabase".emit_event('acknowledgement.created', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id", 'method', v_row."method"), 'acknowledgements/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/acknowledgements');
  perform better_supabase.audit_event(
    event_type => 'acknowledgement.created',
    category => 'security',
    target_type => 'acknowledgement',
    record_id => v_row."id"::text,
    summary => 'acknowledged record',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id", 'method', v_row."method")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id", 'method', v_row."method", 'signatureId', v_row."signature_id", 'acknowledgedAt', v_row."acknowledged_at");
end;
$$;
revoke execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_my_acknowledgements"(tenant uuid, pending_only boolean default true)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectType', x."subject_type",
    'subjectId', x."subject_id",
    'assignmentId', x."id",
    'versionId', "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id"),
    'dueOn', case when x."due_in_days" is null then null else ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days")::text end,
    'overdue', case when x."due_in_days" is not null and ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days") < current_date then true else false end,
    'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = x."subject_type" and ack."subject_id" = x."subject_id" and ack."version_id" = "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id") and ack."user_id" = auth.uid())
  ) order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."acknowledgement_assignments" x
  where x."tenant_id" = list_my_acknowledgements.tenant
    and exists (select 1 from "better_supabase"."acknowledgement_assignments" x where x."tenant_id" = x."tenant_id" and x."subject_type" = x."subject_type" and x."subject_id" = x."subject_id" and (
      (x."principal_type" = 'user' and x."principal_id" = auth.uid()::text)
      or (x."principal_type" = 'role' and x."principal_id" = (select m."role" from "better_supabase"."memberships" m where m."organization_id" = x."tenant_id" and m."user_id" = auth.uid())::text)
      or (x."principal_type" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = x."principal_id" and tm."user_id" = auth.uid()))
    ))
    and (not list_my_acknowledgements.pending_only or not exists (
      select 1 from "better_supabase"."acknowledgements" ack where ack."subject_type" = x."subject_type" and ack."subject_id" = x."subject_id" and ack."version_id" = "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id") and ack."user_id" = auth.uid()
    ))
$$;
revoke execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."acknowledgement_status"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_version uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1;
  if v_tenant is null then
    raise exception 'the record has no assignment' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  if not coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) then
    raise exception 'not allowed to read acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(subject_type, subject_id);
  return jsonb_build_object(
    'versionId', v_version,
    'required', (select count(*) from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id),
    'acknowledged', (select count(*) from "better_supabase"."acknowledgements" ack where ack."subject_type" = acknowledgement_status.subject_type and ack."subject_id" = acknowledgement_status.subject_id and ack."version_id" = v_version),
    'pending', coalesce((select jsonb_agg(jsonb_build_object('userId', m."user_id", 'dueOn', case when x."due_in_days" is null then null else ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = acknowledgement_status.subject_type and v."subject_id" = acknowledgement_status.subject_id and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days")::text end, 'overdue', case when x."due_in_days" is not null and ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = acknowledgement_status.subject_type and v."subject_id" = acknowledgement_status.subject_id and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days") < current_date then true else false end)) from "better_supabase"."memberships" m join "better_supabase"."acknowledgement_assignments" x on x."tenant_id" = m."organization_id" and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text) or (x."principal_type" = 'role' and x."principal_id" = m."role"::text)) where m."organization_id" = v_tenant and x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id and not exists (select 1 from "better_supabase"."acknowledgements" ack where ack."subject_type" = acknowledgement_status.subject_type and ack."subject_id" = acknowledgement_status.subject_id and ack."version_id" = v_version and ack."user_id" = m."user_id")), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."acknowledgement_status"(text, text) from public, anon;
grant execute on function "better_supabase"."acknowledgement_status"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."acknowledgements_of"(subject_type text, subject_id text, version_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', x."user_id", 'versionId', x."version_id", 'method', x."method", 'signatureId', x."signature_id", 'acknowledgedAt', x."acknowledged_at") order by x."acknowledged_at" desc), '[]'::jsonb)
  from "better_supabase"."acknowledgements" x
  where x."subject_type" = $1 and x."subject_id" = $2
    and ($3 is null or x."version_id" = $3)
    and x."tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read'))
$$;
revoke execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) to authenticated, service_role;

create or replace function "better_supabase"."notify_due_acknowledgements"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
  v_due date;
  v_version uuid;
begin
  for v_row in
    select x.*, (select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date as version_on,
      "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id") as version_id
    from "better_supabase"."acknowledgement_assignments" x
    where x."due_in_days" is not null
  loop
    v_due := v_row.version_on + v_row."due_in_days";
    v_version := v_row.version_id;
    if v_version is not null and v_due <= current_date then
      v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_version, 'userId', v_row."principal_id", 'dueOn', v_due::text));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      perform "better_supabase".emit_event('acknowledgement.expired', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_version, 'userId', v_row."principal_id", 'dueOn', v_due::text), 'acknowledgements/' || v_version::text || '/' || v_row."principal_id", (v_row."tenant_id")::text, null, 'better-supabase/acknowledgements');
  perform better_supabase.audit_event(
    event_type => 'acknowledgement.expired',
    category => 'data',
    target_type => 'acknowledgement',
    record_id => v_version::text,
    summary => 'acknowledgement expired',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_version, 'userId', v_row."principal_id", 'dueOn', v_due::text)
  );
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
-- @bsb-hash sha256:8776a0668a7650e4d1be4a1df653b99bf7cf0a150848e8d4cbe5c084ea6efb7c
-- Which member acknowledged which version of a record, with assignments to users, teams and roles, a due date, an effectiveness status and overdue notifications.
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
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Acknowledgements: which member read which version of a record, and the
-- assignments that make a version due.

create table if not exists "app_private"."acknowledgement_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "principal_type" text not null check ("principal_type" in ('user', 'team', 'role')),
  "principal_id" text not null,
  "due_in_days" integer check ("due_in_days" between 1 and 365),
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id")
);
create index if not exists acknowledgement_assignments_principal_idx on "app_private"."acknowledgement_assignments" ("tenant_id", "principal_type", "principal_id");
alter table "app_private"."acknowledgement_assignments" enable row level security;
revoke all on "app_private"."acknowledgement_assignments" from public, anon, authenticated;
grant select on "app_private"."acknowledgement_assignments" to authenticated;
grant all on "app_private"."acknowledgement_assignments" to service_role;
create policy acknowledgement_assignments_read on app_private.acknowledgement_assignments
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

create table if not exists "app_private"."acknowledgements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null,
  "user_id" uuid not null,
  "method" text not null default 'click' check ("method" in ('click', 'signature')),
  "signature_id" uuid,
  "acknowledged_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "version_id", "user_id")
);
create index if not exists acknowledgements_user_idx on "app_private"."acknowledgements" ("tenant_id", "user_id");
create index if not exists acknowledgements_subject_idx on "app_private"."acknowledgements" ("subject_type", "subject_id", "version_id");
alter table "app_private"."acknowledgements" enable row level security;
revoke all on "app_private"."acknowledgements" from public, anon, authenticated;
grant select on "app_private"."acknowledgements" to authenticated;
grant all on "app_private"."acknowledgements" to service_role;
create policy acknowledgements_read on app_private.acknowledgements
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- The current frozen version of a record: the newest frozen version in versions.
create or replace function "app_private"."current_acknowledgement_version"(subject_type text, subject_id text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select v."id"
  from "better_supabase"."versions" v
  where v."subject_type" = $1 and v."subject_id" = $2 and v."frozen"
  order by v."number" desc
  limit 1
$$;
revoke execute on function "app_private"."current_acknowledgement_version"(text, text) from public, anon, authenticated;

-- Assigns a record's current version to a user, a team or a role.
create or replace function "app_private"."assign_acknowledgement"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."acknowledgement_assignments"%rowtype;
  v_version uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'acknowledgements.manage'), false)) then
    raise exception 'not allowed to assign acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  if principal_type not in ('user', 'team', 'role') then
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  if principal_type = 'user' and not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = assign_acknowledgement.tenant and m."user_id" = assign_acknowledgement.principal_id::uuid
  ) then
    raise exception 'the user must be a member of the organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  
  if principal_type = 'role' and not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = assign_acknowledgement.tenant and m."role"::text = assign_acknowledgement.principal_id
  ) then
    raise exception 'the role must exist in the organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  v_version := "app_private"."current_acknowledgement_version"(subject_type, subject_id);
  if v_version is null then
    raise exception 'the record has no frozen version to acknowledge' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  insert into "app_private"."acknowledgement_assignments" ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id", "due_in_days")
  values (assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id, assign_acknowledgement.principal_type, assign_acknowledgement.principal_id, assign_acknowledgement.due_in_days)
  on conflict ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id") do update
    set "due_in_days" = excluded."due_in_days"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."assign_acknowledgement"(uuid, text, text, text, text, integer) from public, anon;
grant execute on function "app_private"."assign_acknowledgement"(uuid, text, text, text, text, integer) to authenticated, service_role;

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
  select * into v_row from "app_private"."acknowledgement_assignments" x where x."id" = unassign_acknowledgement.assignment_id;
  if not found then
    raise exception 'assignment not found' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'acknowledgements.manage'), false)) then
    raise exception 'not allowed to manage acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
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
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'principalType', x."principal_type", 'principalId', x."principal_id", 'dueInDays', x."due_in_days", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."created_at" desc), '[]'::jsonb)
  from "app_private"."acknowledgement_assignments" x
  where x."subject_type" = $1 and x."subject_id" = $2
    and x."tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read'))
$$;
revoke execute on function "app_private"."list_acknowledgement_assignments"(text, text) from public, anon;
grant execute on function "app_private"."list_acknowledgement_assignments"(text, text) to authenticated, service_role;

-- A member acknowledges the current version of a record they are assigned.
create or replace function "app_private"."acknowledge"(subject_type text, subject_id text, version_id uuid default null, signature_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."acknowledgements"%rowtype;
  v_tenant uuid;
  v_version uuid;
  v_current uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select m."organization_id" into v_tenant from "better_supabase"."memberships" m where m."user_id" = auth.uid() limit 1;
  if v_tenant is null or not coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.acknowledge'), false) then
    raise exception 'not allowed to acknowledge' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_current := "app_private"."current_acknowledgement_version"(subject_type, subject_id);
  if v_current is null then
    raise exception 'the record has no frozen version to acknowledge' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  if version_id is not null and version_id <> v_current then
    raise exception 'the record has a newer version' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_VERSION_STALE';
  end if;
  if not exists (select 1 from "app_private"."acknowledgement_assignments" x where x."tenant_id" = v_tenant and x."subject_type" = subject_type and x."subject_id" = subject_id and (
      (x."principal_type" = 'user' and x."principal_id" = auth.uid()::text)
      or (x."principal_type" = 'role' and x."principal_id" = (select m."role" from "better_supabase"."memberships" m where m."organization_id" = v_tenant and m."user_id" = auth.uid())::text)
      
    )) then
    raise exception 'you are not assigned this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  
  insert into "app_private"."acknowledgements" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id", "method", "signature_id")
  values (v_tenant, acknowledge.subject_type, acknowledge.subject_id, coalesce(acknowledge.version_id, v_current), auth.uid(), case when acknowledge.signature_id is null then 'click' else 'signature' end, acknowledge.signature_id)
  on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "app_private"."acknowledgements" x where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id and x."version_id" = coalesce(acknowledge.version_id, v_current) and x."user_id" = auth.uid();
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id", 'method', v_row."method", 'signatureId', v_row."signature_id", 'acknowledgedAt', v_row."acknowledged_at");
end;
$$;
revoke execute on function "app_private"."acknowledge"(text, text, uuid, uuid) from public, anon;
grant execute on function "app_private"."acknowledge"(text, text, uuid, uuid) to authenticated, service_role;

create or replace function "app_private"."list_my_acknowledgements"(tenant uuid, pending_only boolean default true)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectType', x."subject_type",
    'subjectId', x."subject_id",
    'assignmentId', x."id",
    'versionId', "app_private"."current_acknowledgement_version"(x."subject_type", x."subject_id"),
    'dueOn', case when x."due_in_days" is null then null else ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days")::text end,
    'overdue', case when x."due_in_days" is not null and ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days") < current_date then true else false end,
    'acknowledgedAt', (select ack."acknowledged_at" from "app_private"."acknowledgements" ack where ack."subject_type" = x."subject_type" and ack."subject_id" = x."subject_id" and ack."version_id" = "app_private"."current_acknowledgement_version"(x."subject_type", x."subject_id") and ack."user_id" = auth.uid())
  ) order by x."created_at" desc), '[]'::jsonb)
  from "app_private"."acknowledgement_assignments" x
  where x."tenant_id" = list_my_acknowledgements.tenant
    and exists (select 1 from "app_private"."acknowledgement_assignments" x where x."tenant_id" = x."tenant_id" and x."subject_type" = x."subject_type" and x."subject_id" = x."subject_id" and (
      (x."principal_type" = 'user' and x."principal_id" = auth.uid()::text)
      or (x."principal_type" = 'role' and x."principal_id" = (select m."role" from "better_supabase"."memberships" m where m."organization_id" = x."tenant_id" and m."user_id" = auth.uid())::text)
      
    ))
    and (not list_my_acknowledgements.pending_only or not exists (
      select 1 from "app_private"."acknowledgements" ack where ack."subject_type" = x."subject_type" and ack."subject_id" = x."subject_id" and ack."version_id" = "app_private"."current_acknowledgement_version"(x."subject_type", x."subject_id") and ack."user_id" = auth.uid()
    ))
$$;
revoke execute on function "app_private"."list_my_acknowledgements"(uuid, boolean) from public, anon;
grant execute on function "app_private"."list_my_acknowledgements"(uuid, boolean) to authenticated, service_role;

create or replace function "app_private"."acknowledgement_status"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_version uuid;
begin
  select x."tenant_id" into v_tenant from "app_private"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1;
  if v_tenant is null then
    raise exception 'the record has no assignment' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  if not coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) then
    raise exception 'not allowed to read acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "app_private"."current_acknowledgement_version"(subject_type, subject_id);
  return jsonb_build_object(
    'versionId', v_version,
    'required', (select count(*) from "app_private"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id),
    'acknowledged', (select count(*) from "app_private"."acknowledgements" ack where ack."subject_type" = acknowledgement_status.subject_type and ack."subject_id" = acknowledgement_status.subject_id and ack."version_id" = v_version),
    'pending', coalesce((select jsonb_agg(jsonb_build_object('userId', m."user_id", 'dueOn', case when x."due_in_days" is null then null else ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = acknowledgement_status.subject_type and v."subject_id" = acknowledgement_status.subject_id and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days")::text end, 'overdue', case when x."due_in_days" is not null and ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = acknowledgement_status.subject_type and v."subject_id" = acknowledgement_status.subject_id and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days") < current_date then true else false end)) from "better_supabase"."memberships" m join "app_private"."acknowledgement_assignments" x on x."tenant_id" = m."organization_id" and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text) or (x."principal_type" = 'role' and x."principal_id" = m."role"::text)) where m."organization_id" = v_tenant and x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id and not exists (select 1 from "app_private"."acknowledgements" ack where ack."subject_type" = acknowledgement_status.subject_type and ack."subject_id" = acknowledgement_status.subject_id and ack."version_id" = v_version and ack."user_id" = m."user_id")), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "app_private"."acknowledgement_status"(text, text) from public, anon;
grant execute on function "app_private"."acknowledgement_status"(text, text) to authenticated, service_role;

create or replace function "app_private"."acknowledgements_of"(subject_type text, subject_id text, version_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', x."user_id", 'versionId', x."version_id", 'method', x."method", 'signatureId', x."signature_id", 'acknowledgedAt', x."acknowledged_at") order by x."acknowledged_at" desc), '[]'::jsonb)
  from "app_private"."acknowledgements" x
  where x."subject_type" = $1 and x."subject_id" = $2
    and ($3 is null or x."version_id" = $3)
    and x."tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read'))
$$;
revoke execute on function "app_private"."acknowledgements_of"(text, text, uuid) from public, anon;
grant execute on function "app_private"."acknowledgements_of"(text, text, uuid) to authenticated, service_role;

create or replace function "app_private"."notify_due_acknowledgements"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
  v_due date;
  v_version uuid;
begin
  for v_row in
    select x.*, (select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date as version_on,
      "app_private"."current_acknowledgement_version"(x."subject_type", x."subject_id") as version_id
    from "app_private"."acknowledgement_assignments" x
    where x."due_in_days" is not null
  loop
    v_due := v_row.version_on + v_row."due_in_days";
    v_version := v_row.version_id;
    if v_version is not null and v_due <= current_date then
      null;
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
-- @bsb-hash sha256:b98314bc6675bc4ee6284e0e85de43e89cc59904c12f896edbc93cf78014fda8
-- Which member acknowledged which version of a record, with assignments to users, teams and roles, a due date, an effectiveness status and overdue notifications.
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
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Acknowledgements: which member read which version of a record, and the
-- assignments that make a version due.

create table if not exists "better_supabase"."acknowledgement_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "principal_type" text not null check ("principal_type" in ('user', 'team', 'role')),
  "principal_id" text not null,
  "due_in_days" integer check ("due_in_days" between 1 and 365),
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id")
);
create index if not exists acknowledgement_assignments_principal_idx on "better_supabase"."acknowledgement_assignments" ("tenant_id", "principal_type", "principal_id");
alter table "better_supabase"."acknowledgement_assignments" enable row level security;
revoke all on "better_supabase"."acknowledgement_assignments" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgement_assignments" to authenticated;
grant all on "better_supabase"."acknowledgement_assignments" to service_role;
create policy acknowledgement_assignments_read on better_supabase.acknowledgement_assignments
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

create table if not exists "better_supabase"."acknowledgements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null,
  "user_id" uuid not null,
  "method" text not null default 'click' check ("method" in ('click', 'signature')),
  "signature_id" uuid,
  "acknowledged_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "version_id", "user_id")
);
create index if not exists acknowledgements_user_idx on "better_supabase"."acknowledgements" ("tenant_id", "user_id");
create index if not exists acknowledgements_subject_idx on "better_supabase"."acknowledgements" ("subject_type", "subject_id", "version_id");
alter table "better_supabase"."acknowledgements" enable row level security;
revoke all on "better_supabase"."acknowledgements" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgements" to authenticated;
grant all on "better_supabase"."acknowledgements" to service_role;
create policy acknowledgements_read on better_supabase.acknowledgements
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- The current frozen version of a record: the newest frozen version in versions.
create or replace function "better_supabase"."current_acknowledgement_version"(subject_type text, subject_id text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select v."id"
  from "better_supabase"."versions" v
  where v."subject_type" = $1 and v."subject_id" = $2 and v."frozen"
  order by v."number" desc
  limit 1
$$;
revoke execute on function "better_supabase"."current_acknowledgement_version"(text, text) from public, anon, authenticated;

-- Assigns a record's current version to a user, a team or a role.
create or replace function "better_supabase"."assign_acknowledgement"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
  v_version uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'acknowledgements.manage'), false)) then
    raise exception 'not allowed to assign acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  if principal_type not in ('user', 'team', 'role') then
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  if principal_type = 'user' and not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = assign_acknowledgement.tenant and m."user_id" = assign_acknowledgement.principal_id::uuid
  ) then
    raise exception 'the user must be a member of the organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  
  if principal_type = 'role' and not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = assign_acknowledgement.tenant and m."role"::text = assign_acknowledgement.principal_id
  ) then
    raise exception 'the role must exist in the organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(subject_type, subject_id);
  if v_version is null then
    raise exception 'the record has no frozen version to acknowledge' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  insert into "better_supabase"."acknowledgement_assignments" ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id", "due_in_days")
  values (assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id, assign_acknowledgement.principal_type, assign_acknowledgement.principal_id, assign_acknowledgement.due_in_days)
  on conflict ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id") do update
    set "due_in_days" = excluded."due_in_days"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) to authenticated, service_role;

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
  select * into v_row from "better_supabase"."acknowledgement_assignments" x where x."id" = unassign_acknowledgement.assignment_id;
  if not found then
    raise exception 'assignment not found' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'acknowledgements.manage'), false)) then
    raise exception 'not allowed to manage acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
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
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'principalType', x."principal_type", 'principalId', x."principal_id", 'dueInDays', x."due_in_days", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."acknowledgement_assignments" x
  where x."subject_type" = $1 and x."subject_id" = $2
    and x."tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read'))
$$;
revoke execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) from public, anon;
grant execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) to authenticated, service_role;

-- A member acknowledges the current version of a record they are assigned.
create or replace function "better_supabase"."acknowledge"(subject_type text, subject_id text, version_id uuid default null, signature_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."acknowledgements"%rowtype;
  v_tenant uuid;
  v_version uuid;
  v_current uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select m."organization_id" into v_tenant from "better_supabase"."memberships" m where m."user_id" = auth.uid() limit 1;
  if v_tenant is null or not coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.acknowledge'), false) then
    raise exception 'not allowed to acknowledge' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_current := "better_supabase"."current_acknowledgement_version"(subject_type, subject_id);
  if v_current is null then
    raise exception 'the record has no frozen version to acknowledge' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  if version_id is not null and version_id <> v_current then
    raise exception 'the record has a newer version' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_VERSION_STALE';
  end if;
  if not exists (select 1 from "better_supabase"."acknowledgement_assignments" x where x."tenant_id" = v_tenant and x."subject_type" = subject_type and x."subject_id" = subject_id and (
      (x."principal_type" = 'user' and x."principal_id" = auth.uid()::text)
      or (x."principal_type" = 'role' and x."principal_id" = (select m."role" from "better_supabase"."memberships" m where m."organization_id" = v_tenant and m."user_id" = auth.uid())::text)
      
    )) then
    raise exception 'you are not assigned this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  
  insert into "better_supabase"."acknowledgements" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id", "method", "signature_id")
  values (v_tenant, acknowledge.subject_type, acknowledge.subject_id, coalesce(acknowledge.version_id, v_current), auth.uid(), case when acknowledge.signature_id is null then 'click' else 'signature' end, acknowledge.signature_id)
  on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id and x."version_id" = coalesce(acknowledge.version_id, v_current) and x."user_id" = auth.uid();
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id", 'method', v_row."method", 'signatureId', v_row."signature_id", 'acknowledgedAt', v_row."acknowledged_at");
end;
$$;
revoke execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_my_acknowledgements"(tenant uuid, pending_only boolean default true)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectType', x."subject_type",
    'subjectId', x."subject_id",
    'assignmentId', x."id",
    'versionId', "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id"),
    'dueOn', case when x."due_in_days" is null then null else ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days")::text end,
    'overdue', case when x."due_in_days" is not null and ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days") < current_date then true else false end,
    'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = x."subject_type" and ack."subject_id" = x."subject_id" and ack."version_id" = "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id") and ack."user_id" = auth.uid())
  ) order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."acknowledgement_assignments" x
  where x."tenant_id" = list_my_acknowledgements.tenant
    and exists (select 1 from "better_supabase"."acknowledgement_assignments" x where x."tenant_id" = x."tenant_id" and x."subject_type" = x."subject_type" and x."subject_id" = x."subject_id" and (
      (x."principal_type" = 'user' and x."principal_id" = auth.uid()::text)
      or (x."principal_type" = 'role' and x."principal_id" = (select m."role" from "better_supabase"."memberships" m where m."organization_id" = x."tenant_id" and m."user_id" = auth.uid())::text)
      
    ))
    and (not list_my_acknowledgements.pending_only or not exists (
      select 1 from "better_supabase"."acknowledgements" ack where ack."subject_type" = x."subject_type" and ack."subject_id" = x."subject_id" and ack."version_id" = "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id") and ack."user_id" = auth.uid()
    ))
$$;
revoke execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."acknowledgement_status"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_version uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1;
  if v_tenant is null then
    raise exception 'the record has no assignment' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  if not coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) then
    raise exception 'not allowed to read acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(subject_type, subject_id);
  return jsonb_build_object(
    'versionId', v_version,
    'required', (select count(*) from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id),
    'acknowledged', (select count(*) from "better_supabase"."acknowledgements" ack where ack."subject_type" = acknowledgement_status.subject_type and ack."subject_id" = acknowledgement_status.subject_id and ack."version_id" = v_version),
    'pending', coalesce((select jsonb_agg(jsonb_build_object('userId', m."user_id", 'dueOn', case when x."due_in_days" is null then null else ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = acknowledgement_status.subject_type and v."subject_id" = acknowledgement_status.subject_id and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days")::text end, 'overdue', case when x."due_in_days" is not null and ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = acknowledgement_status.subject_type and v."subject_id" = acknowledgement_status.subject_id and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days") < current_date then true else false end)) from "better_supabase"."memberships" m join "better_supabase"."acknowledgement_assignments" x on x."tenant_id" = m."organization_id" and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text) or (x."principal_type" = 'role' and x."principal_id" = m."role"::text)) where m."organization_id" = v_tenant and x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id and not exists (select 1 from "better_supabase"."acknowledgements" ack where ack."subject_type" = acknowledgement_status.subject_type and ack."subject_id" = acknowledgement_status.subject_id and ack."version_id" = v_version and ack."user_id" = m."user_id")), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."acknowledgement_status"(text, text) from public, anon;
grant execute on function "better_supabase"."acknowledgement_status"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."acknowledgements_of"(subject_type text, subject_id text, version_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', x."user_id", 'versionId', x."version_id", 'method', x."method", 'signatureId', x."signature_id", 'acknowledgedAt', x."acknowledged_at") order by x."acknowledged_at" desc), '[]'::jsonb)
  from "better_supabase"."acknowledgements" x
  where x."subject_type" = $1 and x."subject_id" = $2
    and ($3 is null or x."version_id" = $3)
    and x."tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read'))
$$;
revoke execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) to authenticated, service_role;

create or replace function "better_supabase"."notify_due_acknowledgements"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
  v_due date;
  v_version uuid;
begin
  for v_row in
    select x.*, (select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date as version_on,
      "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id") as version_id
    from "better_supabase"."acknowledgement_assignments" x
    where x."due_in_days" is not null
  loop
    v_due := v_row.version_on + v_row."due_in_days";
    v_version := v_row.version_id;
    if v_version is not null and v_due <= current_date then
      null;
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
-- @bsb-hash sha256:3a4b559c99292e6925f1f753b721a952489a03d0b62753529a3f8eb97d5d8080
-- Which member acknowledged which version of a record, with assignments to users, teams and roles, a due date, an effectiveness status and overdue notifications.
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
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Acknowledgements: which member read which version of a record, and the
-- assignments that make a version due.

-- better_supabase.acknowledgement_assignments is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "subject_type" text;
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "subject_id" text;
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "principal_type" text check ("principal_type" in ('user', 'team', 'role'));
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "principal_id" text;
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "due_in_days" integer check ("due_in_days" between 1 and 365);
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "created_by" uuid default auth.uid();
alter table "better_supabase"."acknowledgement_assignments" add column if not exists "created_at" timestamptz not null default now();
create index if not exists acknowledgement_assignments_principal_idx on "better_supabase"."acknowledgement_assignments" ("tenant_id", "principal_type", "principal_id");
alter table "better_supabase"."acknowledgement_assignments" enable row level security;
grant select on "better_supabase"."acknowledgement_assignments" to authenticated;
grant all on "better_supabase"."acknowledgement_assignments" to service_role;
create policy bsb_acknowledgement_assignments_select on better_supabase.acknowledgement_assignments
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- better_supabase.acknowledgements is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."acknowledgements" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."acknowledgements" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."acknowledgements" add column if not exists "subject_type" text;
alter table "better_supabase"."acknowledgements" add column if not exists "subject_id" text;
alter table "better_supabase"."acknowledgements" add column if not exists "version_id" uuid;
alter table "better_supabase"."acknowledgements" add column if not exists "user_id" uuid;
alter table "better_supabase"."acknowledgements" add column if not exists "method" text not null default 'click' check ("method" in ('click', 'signature'));
alter table "better_supabase"."acknowledgements" add column if not exists "signature_id" uuid;
alter table "better_supabase"."acknowledgements" add column if not exists "acknowledged_at" timestamptz not null default now();
create index if not exists acknowledgements_user_idx on "better_supabase"."acknowledgements" ("tenant_id", "user_id");
create index if not exists acknowledgements_subject_idx on "better_supabase"."acknowledgements" ("subject_type", "subject_id", "version_id");
alter table "better_supabase"."acknowledgements" enable row level security;
grant select on "better_supabase"."acknowledgements" to authenticated;
grant all on "better_supabase"."acknowledgements" to service_role;
create policy bsb_acknowledgements_select on better_supabase.acknowledgements
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- The current frozen version of a record: the newest frozen version in versions.
create or replace function "better_supabase"."current_acknowledgement_version"(subject_type text, subject_id text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select v."id"
  from "better_supabase"."versions" v
  where v."subject_type" = $1 and v."subject_id" = $2 and v."frozen"
  order by v."number" desc
  limit 1
$$;
revoke execute on function "better_supabase"."current_acknowledgement_version"(text, text) from public, anon, authenticated;

-- Assigns a record's current version to a user, a team or a role.
create or replace function "better_supabase"."assign_acknowledgement"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
  v_version uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'acknowledgements.manage'), false)) then
    raise exception 'not allowed to assign acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  if principal_type not in ('user', 'team', 'role') then
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  if principal_type = 'user' and not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = assign_acknowledgement.tenant and m."user_id" = assign_acknowledgement.principal_id::uuid
  ) then
    raise exception 'the user must be a member of the organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  
  if principal_type = 'role' and not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = assign_acknowledgement.tenant and m."role"::text = assign_acknowledgement.principal_id
  ) then
    raise exception 'the role must exist in the organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(subject_type, subject_id);
  if v_version is null then
    raise exception 'the record has no frozen version to acknowledge' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  insert into "better_supabase"."acknowledgement_assignments" ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id", "due_in_days")
  values (assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id, assign_acknowledgement.principal_type, assign_acknowledgement.principal_id, assign_acknowledgement.due_in_days)
  on conflict ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id") do update
    set "due_in_days" = excluded."due_in_days"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) to authenticated, service_role;

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
  select * into v_row from "better_supabase"."acknowledgement_assignments" x where x."id" = unassign_acknowledgement.assignment_id;
  if not found then
    raise exception 'assignment not found' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'acknowledgements.manage'), false)) then
    raise exception 'not allowed to manage acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
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
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'principalType', x."principal_type", 'principalId', x."principal_id", 'dueInDays', x."due_in_days", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."acknowledgement_assignments" x
  where x."subject_type" = $1 and x."subject_id" = $2
    and x."tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read'))
$$;
revoke execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) from public, anon;
grant execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) to authenticated, service_role;

-- A member acknowledges the current version of a record they are assigned.
create or replace function "better_supabase"."acknowledge"(subject_type text, subject_id text, version_id uuid default null, signature_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."acknowledgements"%rowtype;
  v_tenant uuid;
  v_version uuid;
  v_current uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select m."organization_id" into v_tenant from "better_supabase"."memberships" m where m."user_id" = auth.uid() limit 1;
  if v_tenant is null or not coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.acknowledge'), false) then
    raise exception 'not allowed to acknowledge' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_current := "better_supabase"."current_acknowledgement_version"(subject_type, subject_id);
  if v_current is null then
    raise exception 'the record has no frozen version to acknowledge' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  if version_id is not null and version_id <> v_current then
    raise exception 'the record has a newer version' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_VERSION_STALE';
  end if;
  if not exists (select 1 from "better_supabase"."acknowledgement_assignments" x where x."tenant_id" = v_tenant and x."subject_type" = subject_type and x."subject_id" = subject_id and (
      (x."principal_type" = 'user' and x."principal_id" = auth.uid()::text)
      or (x."principal_type" = 'role' and x."principal_id" = (select m."role" from "better_supabase"."memberships" m where m."organization_id" = v_tenant and m."user_id" = auth.uid())::text)
      
    )) then
    raise exception 'you are not assigned this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  
  insert into "better_supabase"."acknowledgements" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id", "method", "signature_id")
  values (v_tenant, acknowledge.subject_type, acknowledge.subject_id, coalesce(acknowledge.version_id, v_current), auth.uid(), case when acknowledge.signature_id is null then 'click' else 'signature' end, acknowledge.signature_id)
  on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id and x."version_id" = coalesce(acknowledge.version_id, v_current) and x."user_id" = auth.uid();
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id", 'method', v_row."method", 'signatureId', v_row."signature_id", 'acknowledgedAt', v_row."acknowledged_at");
end;
$$;
revoke execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_my_acknowledgements"(tenant uuid, pending_only boolean default true)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectType', x."subject_type",
    'subjectId', x."subject_id",
    'assignmentId', x."id",
    'versionId', "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id"),
    'dueOn', case when x."due_in_days" is null then null else ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days")::text end,
    'overdue', case when x."due_in_days" is not null and ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days") < current_date then true else false end,
    'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = x."subject_type" and ack."subject_id" = x."subject_id" and ack."version_id" = "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id") and ack."user_id" = auth.uid())
  ) order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."acknowledgement_assignments" x
  where x."tenant_id" = list_my_acknowledgements.tenant
    and exists (select 1 from "better_supabase"."acknowledgement_assignments" x where x."tenant_id" = x."tenant_id" and x."subject_type" = x."subject_type" and x."subject_id" = x."subject_id" and (
      (x."principal_type" = 'user' and x."principal_id" = auth.uid()::text)
      or (x."principal_type" = 'role' and x."principal_id" = (select m."role" from "better_supabase"."memberships" m where m."organization_id" = x."tenant_id" and m."user_id" = auth.uid())::text)
      
    ))
    and (not list_my_acknowledgements.pending_only or not exists (
      select 1 from "better_supabase"."acknowledgements" ack where ack."subject_type" = x."subject_type" and ack."subject_id" = x."subject_id" and ack."version_id" = "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id") and ack."user_id" = auth.uid()
    ))
$$;
revoke execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."acknowledgement_status"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_version uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1;
  if v_tenant is null then
    raise exception 'the record has no assignment' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  if not coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) then
    raise exception 'not allowed to read acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(subject_type, subject_id);
  return jsonb_build_object(
    'versionId', v_version,
    'required', (select count(*) from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id),
    'acknowledged', (select count(*) from "better_supabase"."acknowledgements" ack where ack."subject_type" = acknowledgement_status.subject_type and ack."subject_id" = acknowledgement_status.subject_id and ack."version_id" = v_version),
    'pending', coalesce((select jsonb_agg(jsonb_build_object('userId', m."user_id", 'dueOn', case when x."due_in_days" is null then null else ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = acknowledgement_status.subject_type and v."subject_id" = acknowledgement_status.subject_id and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days")::text end, 'overdue', case when x."due_in_days" is not null and ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = acknowledgement_status.subject_type and v."subject_id" = acknowledgement_status.subject_id and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days") < current_date then true else false end)) from "better_supabase"."memberships" m join "better_supabase"."acknowledgement_assignments" x on x."tenant_id" = m."organization_id" and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text) or (x."principal_type" = 'role' and x."principal_id" = m."role"::text)) where m."organization_id" = v_tenant and x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id and not exists (select 1 from "better_supabase"."acknowledgements" ack where ack."subject_type" = acknowledgement_status.subject_type and ack."subject_id" = acknowledgement_status.subject_id and ack."version_id" = v_version and ack."user_id" = m."user_id")), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."acknowledgement_status"(text, text) from public, anon;
grant execute on function "better_supabase"."acknowledgement_status"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."acknowledgements_of"(subject_type text, subject_id text, version_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', x."user_id", 'versionId', x."version_id", 'method', x."method", 'signatureId', x."signature_id", 'acknowledgedAt', x."acknowledged_at") order by x."acknowledged_at" desc), '[]'::jsonb)
  from "better_supabase"."acknowledgements" x
  where x."subject_type" = $1 and x."subject_id" = $2
    and ($3 is null or x."version_id" = $3)
    and x."tenant_id" in (select better_supabase.tenant_ids_with('acknowledgements.read'))
$$;
revoke execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) to authenticated, service_role;

create or replace function "better_supabase"."notify_due_acknowledgements"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
  v_due date;
  v_version uuid;
begin
  for v_row in
    select x.*, (select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date as version_on,
      "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id") as version_id
    from "better_supabase"."acknowledgement_assignments" x
    where x."due_in_days" is not null
  loop
    v_due := v_row.version_on + v_row."due_in_days";
    v_version := v_row.version_id;
    if v_version is not null and v_due <= current_date then
      null;
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
-- @bsb-hash sha256:cdc8b319eef42e9966a8ae84d392ceb003da72aa4dce737af7813f634a925be4
-- Which member acknowledged which version of a record, with assignments to users, teams and roles, a due date, an effectiveness status and overdue notifications.
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
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Acknowledgements: which member read which version of a record, and the
-- assignments that make a version due.

create table if not exists "better_supabase"."acknowledgement_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "principal_type" text not null check ("principal_type" in ('user', 'team', 'role')),
  "principal_id" text not null,
  "due_in_days" integer check ("due_in_days" between 1 and 365),
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("org_id", "subject_type", "subject_id", "principal_type", "principal_id")
);
create index if not exists acknowledgement_assignments_principal_idx on "better_supabase"."acknowledgement_assignments" ("org_id", "principal_type", "principal_id");
alter table "better_supabase"."acknowledgement_assignments" enable row level security;
revoke all on "better_supabase"."acknowledgement_assignments" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgement_assignments" to authenticated;
grant all on "better_supabase"."acknowledgement_assignments" to service_role;
create policy acknowledgement_assignments_read on better_supabase.acknowledgement_assignments
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

create table if not exists "better_supabase"."acknowledgements" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version_id" uuid not null,
  "user_id" uuid not null,
  "method" text not null default 'click' check ("method" in ('click', 'signature')),
  "signature_id" uuid,
  "acknowledged_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "version_id", "user_id")
);
create index if not exists acknowledgements_user_idx on "better_supabase"."acknowledgements" ("org_id", "user_id");
create index if not exists acknowledgements_subject_idx on "better_supabase"."acknowledgements" ("subject_type", "subject_id", "version_id");
alter table "better_supabase"."acknowledgements" enable row level security;
revoke all on "better_supabase"."acknowledgements" from public, anon, authenticated;
grant select on "better_supabase"."acknowledgements" to authenticated;
grant all on "better_supabase"."acknowledgements" to service_role;
create policy acknowledgements_read on better_supabase.acknowledgements
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('acknowledgements.read')));

-- The current frozen version of a record: the newest frozen version in versions.
create or replace function "better_supabase"."current_acknowledgement_version"(subject_type text, subject_id text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select v."id"
  from "better_supabase"."versions" v
  where v."subject_type" = $1 and v."subject_id" = $2 and v."frozen"
  order by v."number" desc
  limit 1
$$;
revoke execute on function "better_supabase"."current_acknowledgement_version"(text, text) from public, anon, authenticated;

-- Assigns a record's current version to a user, a team or a role.
create or replace function "better_supabase"."assign_acknowledgement"(tenant uuid, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
  v_version uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'acknowledgements.manage'), false)) then
    raise exception 'not allowed to assign acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  if principal_type not in ('user', 'team', 'role') then
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  if principal_type = 'user' and not exists (
    select 1 from "better_supabase"."memberships" m where m."org_id" = assign_acknowledgement.tenant and m."user_id" = assign_acknowledgement.principal_id::uuid
  ) then
    raise exception 'the user must be a member of the organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  
  if principal_type = 'role' and not exists (
    select 1 from "better_supabase"."memberships" m where m."org_id" = assign_acknowledgement.tenant and m."role"::text = assign_acknowledgement.principal_id
  ) then
    raise exception 'the role must exist in the organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(subject_type, subject_id);
  if v_version is null then
    raise exception 'the record has no frozen version to acknowledge' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  insert into "better_supabase"."acknowledgement_assignments" ("org_id", "subject_type", "subject_id", "principal_type", "principal_id", "due_in_days")
  values (assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id, assign_acknowledgement.principal_type, assign_acknowledgement.principal_id, assign_acknowledgement.due_in_days)
  on conflict ("org_id", "subject_type", "subject_id", "principal_type", "principal_id") do update
    set "due_in_days" = excluded."due_in_days"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."assign_acknowledgement"(uuid, text, text, text, text, integer) to authenticated, service_role;

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
  select * into v_row from "better_supabase"."acknowledgement_assignments" x where x."id" = unassign_acknowledgement.assignment_id;
  if not found then
    raise exception 'assignment not found' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'acknowledgements.manage'), false)) then
    raise exception 'not allowed to manage acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
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
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'principalType', x."principal_type", 'principalId', x."principal_id", 'dueInDays', x."due_in_days", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."acknowledgement_assignments" x
  where x."subject_type" = $1 and x."subject_id" = $2
    and x."org_id" in (select better_supabase.tenant_ids_with('acknowledgements.read'))
$$;
revoke execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) from public, anon;
grant execute on function "better_supabase"."list_acknowledgement_assignments"(text, text) to authenticated, service_role;

-- A member acknowledges the current version of a record they are assigned.
create or replace function "better_supabase"."acknowledge"(subject_type text, subject_id text, version_id uuid default null, signature_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."acknowledgements"%rowtype;
  v_tenant uuid;
  v_version uuid;
  v_current uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select m."org_id" into v_tenant from "better_supabase"."memberships" m where m."user_id" = auth.uid() limit 1;
  if v_tenant is null or not coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.acknowledge'), false) then
    raise exception 'not allowed to acknowledge' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_current := "better_supabase"."current_acknowledgement_version"(subject_type, subject_id);
  if v_current is null then
    raise exception 'the record has no frozen version to acknowledge' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  if version_id is not null and version_id <> v_current then
    raise exception 'the record has a newer version' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_VERSION_STALE';
  end if;
  if not exists (select 1 from "better_supabase"."acknowledgement_assignments" x where x."org_id" = v_tenant and x."subject_type" = subject_type and x."subject_id" = subject_id and (
      (x."principal_type" = 'user' and x."principal_id" = auth.uid()::text)
      or (x."principal_type" = 'role' and x."principal_id" = (select m."role" from "better_supabase"."memberships" m where m."org_id" = v_tenant and m."user_id" = auth.uid())::text)
      
    )) then
    raise exception 'you are not assigned this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  
  insert into "better_supabase"."acknowledgements" ("org_id", "subject_type", "subject_id", "version_id", "user_id", "method", "signature_id")
  values (v_tenant, acknowledge.subject_type, acknowledge.subject_id, coalesce(acknowledge.version_id, v_current), auth.uid(), case when acknowledge.signature_id is null then 'click' else 'signature' end, acknowledge.signature_id)
  on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id and x."version_id" = coalesce(acknowledge.version_id, v_current) and x."user_id" = auth.uid();
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id", 'method', v_row."method", 'signatureId', v_row."signature_id", 'acknowledgedAt', v_row."acknowledged_at");
end;
$$;
revoke execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledge"(text, text, uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_my_acknowledgements"(tenant uuid, pending_only boolean default true)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectType', x."subject_type",
    'subjectId', x."subject_id",
    'assignmentId', x."id",
    'versionId', "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id"),
    'dueOn', case when x."due_in_days" is null then null else ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days")::text end,
    'overdue', case when x."due_in_days" is not null and ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days") < current_date then true else false end,
    'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = x."subject_type" and ack."subject_id" = x."subject_id" and ack."version_id" = "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id") and ack."user_id" = auth.uid())
  ) order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."acknowledgement_assignments" x
  where x."org_id" = list_my_acknowledgements.tenant
    and exists (select 1 from "better_supabase"."acknowledgement_assignments" x where x."org_id" = x."org_id" and x."subject_type" = x."subject_type" and x."subject_id" = x."subject_id" and (
      (x."principal_type" = 'user' and x."principal_id" = auth.uid()::text)
      or (x."principal_type" = 'role' and x."principal_id" = (select m."role" from "better_supabase"."memberships" m where m."org_id" = x."org_id" and m."user_id" = auth.uid())::text)
      
    ))
    and (not list_my_acknowledgements.pending_only or not exists (
      select 1 from "better_supabase"."acknowledgements" ack where ack."subject_type" = x."subject_type" and ack."subject_id" = x."subject_id" and ack."version_id" = "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id") and ack."user_id" = auth.uid()
    ))
$$;
revoke execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_my_acknowledgements"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."acknowledgement_status"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_version uuid;
begin
  select x."org_id" into v_tenant from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1;
  if v_tenant is null then
    raise exception 'the record has no assignment' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  if not coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) then
    raise exception 'not allowed to read acknowledgements' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(subject_type, subject_id);
  return jsonb_build_object(
    'versionId', v_version,
    'required', (select count(*) from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id),
    'acknowledged', (select count(*) from "better_supabase"."acknowledgements" ack where ack."subject_type" = acknowledgement_status.subject_type and ack."subject_id" = acknowledgement_status.subject_id and ack."version_id" = v_version),
    'pending', coalesce((select jsonb_agg(jsonb_build_object('userId', m."user_id", 'dueOn', case when x."due_in_days" is null then null else ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = acknowledgement_status.subject_type and v."subject_id" = acknowledgement_status.subject_id and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days")::text end, 'overdue', case when x."due_in_days" is not null and ((select v."created_at" from "better_supabase"."versions" v where v."subject_type" = acknowledgement_status.subject_type and v."subject_id" = acknowledgement_status.subject_id and v."frozen" order by v."number" desc limit 1)::date + x."due_in_days") < current_date then true else false end)) from "better_supabase"."memberships" m join "better_supabase"."acknowledgement_assignments" x on x."org_id" = m."org_id" and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text) or (x."principal_type" = 'role' and x."principal_id" = m."role"::text)) where m."org_id" = v_tenant and x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id and not exists (select 1 from "better_supabase"."acknowledgements" ack where ack."subject_type" = acknowledgement_status.subject_type and ack."subject_id" = acknowledgement_status.subject_id and ack."version_id" = v_version and ack."user_id" = m."user_id")), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."acknowledgement_status"(text, text) from public, anon;
grant execute on function "better_supabase"."acknowledgement_status"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."acknowledgements_of"(subject_type text, subject_id text, version_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', x."user_id", 'versionId', x."version_id", 'method', x."method", 'signatureId', x."signature_id", 'acknowledgedAt', x."acknowledged_at") order by x."acknowledged_at" desc), '[]'::jsonb)
  from "better_supabase"."acknowledgements" x
  where x."subject_type" = $1 and x."subject_id" = $2
    and ($3 is null or x."version_id" = $3)
    and x."org_id" in (select better_supabase.tenant_ids_with('acknowledgements.read'))
$$;
revoke execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."acknowledgements_of"(text, text, uuid) to authenticated, service_role;

create or replace function "better_supabase"."notify_due_acknowledgements"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
  v_due date;
  v_version uuid;
begin
  for v_row in
    select x.*, (select v."created_at" from "better_supabase"."versions" v where v."subject_type" = x."subject_type" and v."subject_id" = x."subject_id" and v."frozen" order by v."number" desc limit 1)::date as version_on,
      "better_supabase"."current_acknowledgement_version"(x."subject_type", x."subject_id") as version_id
    from "better_supabase"."acknowledgement_assignments" x
    where x."due_in_days" is not null
  loop
    v_due := v_row.version_on + v_row."due_in_days";
    v_version := v_row.version_id;
    if v_version is not null and v_due <= current_date then
      null;
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
