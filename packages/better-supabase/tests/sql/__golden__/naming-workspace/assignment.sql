-- ==== schema supabase/schemas/900_better_supabase_134_assignment.sql
-- better-supabase module: assignment
-- @bsb-block assignment@1 managed
-- @bsb-hash sha256:51ce368907297135c7ba80136f2961ba6111c37b4fbc06bf49e132b70a853fea
-- Queues of members that pick an owner for new leads, deals or tickets: round robin or weighted, within a territory written as rule conditions, with a log of every pick.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."assignment_queues";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."assignment_queues";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."assignment_queues";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."assignment_queues";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."assignment_queues";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."assignment_queue_members";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."assignment_queue_members";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."assignment_queue_members";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."assignment_queue_members";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."assignment_queue_members";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."assignments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."assignments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."assignments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."assignments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Assignment: queues of members that pick an owner for new records, by
-- round robin or weight, within a territory of rule conditions.
create table if not exists "better_supabase"."assignment_queues" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "strategy" text not null default 'round_robin' check ("strategy" in ('round_robin', 'weighted')),
  "conditions" jsonb check ("conditions" is null or jsonb_typeof("conditions") = 'object'),
  "rank" integer not null default 0,
  "enabled" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "name")
);
create index if not exists assignment_queues_order_idx on "better_supabase"."assignment_queues" ("tenant_id", "subject_type", "rank") where "enabled";
alter table "better_supabase"."assignment_queues" enable row level security;
revoke all on "better_supabase"."assignment_queues" from public, anon, authenticated;
grant select on "better_supabase"."assignment_queues" to authenticated;
grant all on "better_supabase"."assignment_queues" to service_role;
create table if not exists "better_supabase"."assignment_queue_members" (
  "queue_id" uuid not null references "better_supabase"."assignment_queues" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "weight" integer not null default 1 check ("weight" between 1 and 100),
  "active" boolean not null default true,
  "credit" bigint not null default 0,
  "assigned_count" integer not null default 0,
  "last_assigned_at" timestamptz,
  primary key ("queue_id", "user_id")
);
create index if not exists assignment_queue_members_user_idx on "better_supabase"."assignment_queue_members" ("user_id");
alter table "better_supabase"."assignment_queue_members" enable row level security;
revoke all on "better_supabase"."assignment_queue_members" from public, anon, authenticated;
grant select on "better_supabase"."assignment_queue_members" to authenticated;
grant all on "better_supabase"."assignment_queue_members" to service_role;
create table if not exists "better_supabase"."assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "queue_id" uuid references "better_supabase"."assignment_queues" ("id") on delete set null,
  "subject_type" text not null,
  "subject_id" text not null,
  "user_id" uuid references auth.users (id) on delete set null,
  "assigned_at" timestamptz not null default now()
);
create index if not exists assignments_subject_idx on "better_supabase"."assignments" ("tenant_id", "subject_type", "subject_id", "assigned_at" desc);
create index if not exists assignments_queue_idx on "better_supabase"."assignments" ("queue_id") where "queue_id" is not null;
create index if not exists assignments_user_idx on "better_supabase"."assignments" ("user_id") where "user_id" is not null;
alter table "better_supabase"."assignments" enable row level security;
revoke all on "better_supabase"."assignments" from public, anon, authenticated;
grant select on "better_supabase"."assignments" to authenticated;
grant all on "better_supabase"."assignments" to service_role;
drop policy if exists assignment_queues_read on "better_supabase"."assignment_queues";
create policy assignment_queues_read on "better_supabase"."assignment_queues" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('assignment.read')));
drop policy if exists assignment_queue_members_read on "better_supabase"."assignment_queue_members";
create policy assignment_queue_members_read on "better_supabase"."assignment_queue_members" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('assignment.read')));
drop policy if exists assignments_read on "better_supabase"."assignments";
create policy assignments_read on "better_supabase"."assignments" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('assignment.read')));

-- Creates or changes a queue: queue is { id?, name, subjectType, strategy?,
-- conditions?, rank?, enabled? }. conditions, the queue's territory, is a
-- FilterQuery over the subject type's rule fields; null matches every record.
create or replace function "better_supabase"."save_assignment_queue"(tenant uuid, queue jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_old "better_supabase"."assignment_queues";
  v_row "better_supabase"."assignment_queues";
  v_type text;
  v_conditions jsonb;
  v_fields jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(better_supabase.can('tenant', save_assignment_queue.tenant, 'assignment.manage'), false) then
    raise exception 'You need assignment.manage to change assignment queues' using errcode = '42501', hint = 'ASSIGNMENT_FORBIDDEN';
  end if;
  if jsonb_typeof(queue) is distinct from 'object' then
    raise exception 'queue must be an object' using errcode = '22023', hint = 'ASSIGNMENT_INVALID';
  end if;
  v_id := nullif(queue ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."assignment_queues" x
    where x."id" = v_id and x."tenant_id" = save_assignment_queue.tenant for update;
    if v_old."id" is null then
      raise exception 'No assignment queue in this organization has this id' using errcode = 'P0002', hint = 'ASSIGNMENT_NOT_FOUND';
    end if;
  end if;
  v_type := coalesce(queue ->> 'subjectType', v_old."subject_type");
  if v_type is null or v_type !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'A queue needs a subject type' using errcode = '22023', hint = 'ASSIGNMENT_INVALID';
  end if;
  v_conditions := case when queue ? 'conditions' then nullif(queue -> 'conditions', 'null'::jsonb) else v_old."conditions" end;
  if v_conditions is not null then
    v_fields := "better_supabase"."rule_field_map"(v_type);
    if v_fields = '{}'::jsonb then
      raise exception 'No rule fields for this subject type; sync them first' using errcode = '22023', hint = 'ASSIGNMENT_FIELDS_MISSING';
    end if;
    perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."assignment_queues" ("tenant_id", "name", "subject_type", "strategy", "conditions", "rank", "enabled")
    values (save_assignment_queue.tenant, trim(queue ->> 'name'), v_type, coalesce(queue ->> 'strategy', 'round_robin'),
      v_conditions, coalesce((queue ->> 'rank')::integer, 0), coalesce((queue ->> 'enabled')::boolean, true))
    returning * into v_row;
  else
    update "better_supabase"."assignment_queues" x set
      "name" = coalesce(trim(queue ->> 'name'), x."name"),
      "subject_type" = v_type,
      "strategy" = coalesce(queue ->> 'strategy', x."strategy"),
      "conditions" = v_conditions,
      "rank" = coalesce((queue ->> 'rank')::integer, x."rank"),
      "enabled" = coalesce((queue ->> 'enabled')::boolean, x."enabled"),
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'subjectType', v_row."subject_type", 'strategy', v_row."strategy"::text, 'conditions', v_row."conditions", 'rank', v_row."rank", 'enabled', v_row."enabled", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'members', coalesce((
      select jsonb_agg(jsonb_build_object('userId', z."user_id", 'weight', z."weight", 'active', z."active", 'assignedCount', z."assigned_count", 'lastAssignedAt', z."last_assigned_at") order by z."user_id")
      from "better_supabase"."assignment_queue_members" z where z."queue_id" = v_row."id"
    ), '[]'::jsonb));
exception
  when unique_violation then
    raise exception 'Another assignment queue in this organization has this name' using errcode = '23505', hint = 'ASSIGNMENT_NAME_TAKEN';
  when check_violation or not_null_violation then
    raise exception 'A queue needs a name of at most 200 characters and a strategy of round_robin or weighted' using errcode = '22023', hint = 'ASSIGNMENT_INVALID';
end;
$$;
revoke execute on function "better_supabase"."save_assignment_queue"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_assignment_queue"(uuid, jsonb) to authenticated, service_role;

-- Replaces a queue's members: members is [{ userId, weight?, active? }], each
-- a member of the queue's organization. Members who stay keep their place in
-- the rotation.
create or replace function "better_supabase"."set_assignment_members"(queue uuid, members jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_queue "better_supabase"."assignment_queues";
  v_item jsonb;
  v_users uuid[] := '{}';
  v_user uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_queue from "better_supabase"."assignment_queues" x where x."id" = set_assignment_members.queue for update;
  if v_queue."id" is null or not coalesce(better_supabase.can('tenant', v_queue."tenant_id", 'assignment.manage'), false) then
    raise exception 'No assignment queue you can manage has this id' using errcode = 'P0002', hint = 'ASSIGNMENT_NOT_FOUND';
  end if;
  if jsonb_typeof(members) is distinct from 'array' or jsonb_array_length(members) > 200 then
    raise exception 'members must be an array of at most 200 entries' using errcode = '22023', hint = 'ASSIGNMENT_INVALID';
  end if;
  for v_item in select x.value from jsonb_array_elements(members) x loop
    v_user := nullif(v_item ->> 'userId', '')::uuid;
    if v_user is null or not exists (select 1 from "better_supabase"."memberships" mm where mm."workspace_id" = v_queue."tenant_id" and mm."user_id" = v_user and mm."disabled_at" is null) then
      raise exception 'Every member must be a member of the queue''s organization' using errcode = '22023', hint = 'ASSIGNMENT_MEMBER_INVALID';
    end if;
    v_users := v_users || v_user;
    insert into "better_supabase"."assignment_queue_members" ("queue_id", "tenant_id", "user_id", "weight", "active")
    values (v_queue."id", v_queue."tenant_id", v_user, coalesce((v_item ->> 'weight')::integer, 1), coalesce((v_item ->> 'active')::boolean, true))
    on conflict ("queue_id", "user_id") do update set
      "weight" = excluded."weight",
      "active" = excluded."active";
  end loop;
  delete from "better_supabase"."assignment_queue_members" z where z."queue_id" = v_queue."id" and not (z."user_id" = any (v_users));
  return jsonb_build_object('id', v_queue."id", 'organizationId', v_queue."tenant_id", 'name', v_queue."name", 'subjectType', v_queue."subject_type", 'strategy', v_queue."strategy"::text, 'conditions', v_queue."conditions", 'rank', v_queue."rank", 'enabled', v_queue."enabled", 'createdAt', v_queue."created_at", 'updatedAt', v_queue."updated_at", 'members', coalesce((
      select jsonb_agg(jsonb_build_object('userId', z."user_id", 'weight', z."weight", 'active', z."active", 'assignedCount', z."assigned_count", 'lastAssignedAt', z."last_assigned_at") order by z."user_id")
      from "better_supabase"."assignment_queue_members" z where z."queue_id" = v_queue."id"
    ), '[]'::jsonb));
exception when check_violation then
  raise exception 'A member''s weight is between 1 and 100' using errcode = '22023', hint = 'ASSIGNMENT_INVALID';
end;
$$;
revoke execute on function "better_supabase"."set_assignment_members"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_assignment_members"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."remove_assignment_queue"(queue uuid)
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
  select x."tenant_id" into v_tenant from "better_supabase"."assignment_queues" x where x."id" = remove_assignment_queue.queue;
  if v_tenant is null then
    return false;
  end if;
  if not coalesce(better_supabase.can('tenant', v_tenant, 'assignment.manage'), false) then
    raise exception 'You need assignment.manage to remove an assignment queue' using errcode = '42501', hint = 'ASSIGNMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."assignment_queues" x where x."id" = remove_assignment_queue.queue;
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_assignment_queue"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_assignment_queue"(uuid) to authenticated, service_role;

-- The organization's queues, optionally of one subject type, in the order
-- assign tries them, with their members.
create or replace function "better_supabase"."list_assignment_queues"(tenant uuid, subject_type text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(better_supabase.can('tenant', list_assignment_queues.tenant, 'assignment.read'), false) then
    raise exception 'You need assignment.read to list assignment queues' using errcode = '42501', hint = 'ASSIGNMENT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'subjectType', x."subject_type", 'strategy', x."strategy"::text, 'conditions', x."conditions", 'rank', x."rank", 'enabled', x."enabled", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'members', coalesce((
      select jsonb_agg(jsonb_build_object('userId', z."user_id", 'weight', z."weight", 'active', z."active", 'assignedCount', z."assigned_count", 'lastAssignedAt', z."last_assigned_at") order by z."user_id")
      from "better_supabase"."assignment_queue_members" z where z."queue_id" = x."id"
    ), '[]'::jsonb)) order by x."subject_type", x."rank", x."name")
    from "better_supabase"."assignment_queues" x
    where x."tenant_id" = list_assignment_queues.tenant
      and (list_assignment_queues.subject_type is null or x."subject_type" = list_assignment_queues.subject_type)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_assignment_queues"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_assignment_queues"(uuid, text) to authenticated, service_role;

-- Picks an owner for a record: the first enabled queue of the subject type,
-- by rank, whose conditions match subject (the record's fields, keyed as the
-- rule fields' columns) and that has an active member. round_robin picks the
-- member assigned longest ago; weighted spreads records by weight (smooth
-- weighted round robin). Returns { queueId, userId, strategy }, or null when
-- no queue matches. The app writes the owner; this logs the pick.
create or replace function "better_supabase"."assign_subject"(tenant uuid, subject_type text, subject_id text, subject jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_queue "better_supabase"."assignment_queues";
  v_fields jsonb;
  v_user uuid;
  v_total bigint;
  v_log uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', assign_subject.tenant, 'assignment.assign'), false)) then
    raise exception 'You need assignment.assign to assign records' using errcode = '42501', hint = 'ASSIGNMENT_FORBIDDEN';
  end if;
  if subject_id is null or length(subject_id) > 200 then
    raise exception 'subject_id must be at most 200 characters' using errcode = '22023', hint = 'ASSIGNMENT_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(assign_subject.subject_type);
  for v_queue in
    select * from "better_supabase"."assignment_queues" x
    where x."tenant_id" = assign_subject.tenant and x."subject_type" = assign_subject.subject_type and x."enabled"
    order by x."rank", x."name"
  loop
    if v_queue."conditions" is not null
      and not "better_supabase"."rule_matches"(v_queue."conditions", coalesce(assign_subject.subject, '{}'::jsonb), v_fields, 'UTC', now()) then
      continue;
    end if;
    perform 1 from "better_supabase"."assignment_queues" x where x."id" = v_queue."id" for update;
    if v_queue."strategy"::text = 'weighted' then
      select coalesce(sum(z."weight"), 0) into v_total from "better_supabase"."assignment_queue_members" z
      where z."queue_id" = v_queue."id" and z."active" and exists (select 1 from "better_supabase"."memberships" mw where mw."workspace_id" = v_queue."tenant_id" and mw."user_id" = z."user_id" and mw."disabled_at" is null);
      if v_total = 0 then
        continue;
      end if;
      update "better_supabase"."assignment_queue_members" z set "credit" = z."credit" + z."weight"
      where z."queue_id" = v_queue."id" and z."active" and exists (select 1 from "better_supabase"."memberships" mw where mw."workspace_id" = v_queue."tenant_id" and mw."user_id" = z."user_id" and mw."disabled_at" is null);
      select z."user_id" into v_user from "better_supabase"."assignment_queue_members" z
      where z."queue_id" = v_queue."id" and z."active" and exists (select 1 from "better_supabase"."memberships" mw where mw."workspace_id" = v_queue."tenant_id" and mw."user_id" = z."user_id" and mw."disabled_at" is null)
      order by z."credit" desc, z."last_assigned_at" nulls first, z."user_id"
      limit 1;
      update "better_supabase"."assignment_queue_members" z set "credit" = z."credit" - v_total
      where z."queue_id" = v_queue."id" and z."user_id" = v_user;
    else
      select z."user_id" into v_user from "better_supabase"."assignment_queue_members" z
      where z."queue_id" = v_queue."id" and z."active" and exists (select 1 from "better_supabase"."memberships" mr where mr."workspace_id" = v_queue."tenant_id" and mr."user_id" = z."user_id" and mr."disabled_at" is null)
      order by z."last_assigned_at" nulls first, z."user_id"
      limit 1;
      if v_user is null then
        continue;
      end if;
    end if;
    update "better_supabase"."assignment_queue_members" z set "last_assigned_at" = clock_timestamp(), "assigned_count" = z."assigned_count" + 1
    where z."queue_id" = v_queue."id" and z."user_id" = v_user;
    insert into "better_supabase"."assignments" ("tenant_id", "queue_id", "subject_type", "subject_id", "user_id")
    values (v_queue."tenant_id", v_queue."id", v_queue."subject_type", assign_subject.subject_id, v_user)
    returning "id" into v_log;
    null;
    return jsonb_build_object('queueId', v_queue."id", 'userId', v_user, 'strategy', v_queue."strategy"::text);
  end loop;
  return null;
end;
$$;
revoke execute on function "better_supabase"."assign_subject"(uuid, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."assign_subject"(uuid, text, text, jsonb) to authenticated, service_role;

-- The picks for a record, newest first: { queueId, userId, assignedAt }.
create or replace function "better_supabase"."assignment_history"(tenant uuid, subject_type text, subject_id text, max_count integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(better_supabase.can('tenant', assignment_history.tenant, 'assignment.read'), false) then
    raise exception 'You need assignment.read to read assignments' using errcode = '42501', hint = 'ASSIGNMENT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('queueId', y."queue_id", 'userId', y."user_id", 'assignedAt', y."assigned_at") order by y."assigned_at" desc, y."id")
    from (
      select x.* from "better_supabase"."assignments" x
      where x."tenant_id" = assignment_history.tenant and x."subject_type" = assignment_history.subject_type
        and x."subject_id" = assignment_history.subject_id
      order by x."assigned_at" desc, x."id"
      limit least(greatest(coalesce(assignment_history.max_count, 20), 1), 200)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."assignment_history"(uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."assignment_history"(uuid, text, text, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."assignment_queues";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."assignment_queues";
create policy bsb_tenant_scope_select on "better_supabase"."assignment_queues" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assignment.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."assignment_queues";
create policy bsb_tenant_scope_insert on "better_supabase"."assignment_queues" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."assignment_queues";
create policy bsb_tenant_scope_update on "better_supabase"."assignment_queues" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."assignment_queues";
create policy bsb_tenant_scope_delete on "better_supabase"."assignment_queues" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."assignment_queue_members";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."assignment_queue_members";
create policy bsb_tenant_scope_select on "better_supabase"."assignment_queue_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assignment.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."assignment_queue_members";
create policy bsb_tenant_scope_insert on "better_supabase"."assignment_queue_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."assignment_queue_members";
create policy bsb_tenant_scope_update on "better_supabase"."assignment_queue_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."assignment_queue_members";
create policy bsb_tenant_scope_delete on "better_supabase"."assignment_queue_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."assignments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."assignments";
create policy bsb_tenant_scope_select on "better_supabase"."assignments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assignment.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."assignments";
create policy bsb_tenant_scope_insert on "better_supabase"."assignments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."assignments";
create policy bsb_tenant_scope_update on "better_supabase"."assignments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."assignments";
create policy bsb_tenant_scope_delete on "better_supabase"."assignments" as restrictive
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

-- ==== data supabase/better-supabase-data/900_better_supabase_134_assignment.sql
-- better-supabase module: assignment
-- @bsb-block-data assignment
-- @bsb-hash sha256:336c65d0cac5c9c18ec22385c79dea4ed6a56ebaee602d9ffd157ca812e472aa
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('assignment', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
