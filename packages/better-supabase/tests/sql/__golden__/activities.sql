-- ==== alone: schema supabase/schemas/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block activities@3 managed
-- @bsb-hash sha256:e0553036e1091d44a39749e34d36b6d3d33e23d21341546c2a3b51e0e728cad5
-- Calls, emails, meetings, notes and tasks logged on one or more registered records, with an owner, a due time and an outcome, a record's timeline, its next step and a member's open tasks.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."activities";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagement_subjects";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Calls, emails, meetings, notes and tasks logged on one or more records.
create table if not exists "better_supabase"."activities" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "type" text not null,
  "title" text not null check (length("title") between 1 and 500),
  "body" text,
  "outcome" text,
  "owner_user_id" uuid,
  "due_at" timestamptz,
  "done_at" timestamptz,
  "duration_seconds" integer check ("duration_seconds" >= 0),
  "external_ref" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "activities_owner_open_idx" on "better_supabase"."activities" ("tenant_id", "owner_user_id", "due_at") where "done_at" is null;
create index if not exists "activities_tenant_created_idx" on "better_supabase"."activities" ("tenant_id", "created_at" desc);
create unique index if not exists "activities_external_ref_idx" on "better_supabase"."activities" ("tenant_id", "external_ref") where "external_ref" is not null;
-- Progress notes: who reads an engagement, when it locks, its addenda and the
-- in-error flag.
alter table "better_supabase"."activities" add column if not exists "audience" text not null default 'team' check ("audience" in ('team', 'subject', 'restricted'));
alter table "better_supabase"."activities" add column if not exists "restricted_roles" text[];
alter table "better_supabase"."activities" add column if not exists "category" text check (length("category") between 1 and 63);
alter table "better_supabase"."activities" add column if not exists "locked_at" timestamptz;
alter table "better_supabase"."activities" add column if not exists "amends_id" uuid references "better_supabase"."activities" ("id") on delete cascade;
alter table "better_supabase"."activities" add column if not exists "goal_id" uuid;
alter table "better_supabase"."activities" add column if not exists "marked_error_at" timestamptz;
alter table "better_supabase"."activities" add column if not exists "marked_error_by" uuid;
alter table "better_supabase"."activities" add column if not exists "marked_error_reason" text check (length("marked_error_reason") between 1 and 2000);
create index if not exists "activities_amends_idx" on "better_supabase"."activities" ("amends_id");
alter table "better_supabase"."activities" enable row level security;
revoke all on "better_supabase"."activities" from public, anon, authenticated;
grant select on "better_supabase"."activities" to authenticated;
grant all on "better_supabase"."activities" to service_role;
create table if not exists "better_supabase"."engagement_subjects" (
  "tenant_id" uuid not null,
  "activity_id" uuid not null references "better_supabase"."activities" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "position" integer not null default 1,
  primary key ("activity_id", "subject_type", "subject_id")
);
create index if not exists engagement_subjects_subject_idx on "better_supabase"."engagement_subjects" ("subject_type", "subject_id");
alter table "better_supabase"."engagement_subjects" enable row level security;
revoke all on "better_supabase"."engagement_subjects" from public, anon, authenticated;
grant select on "better_supabase"."engagement_subjects" to authenticated;
grant all on "better_supabase"."engagement_subjects" to service_role;
-- A link is visible when its record is; an engagement when one of its
-- records is, or it has none. A guest of a record reads its subject notes.
drop policy if exists engagement_subjects_read on "better_supabase"."engagement_subjects";
create policy engagement_subjects_read on "better_supabase"."engagement_subjects"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));
drop policy if exists activities_read on "better_supabase"."activities";
create policy activities_read on "better_supabase"."activities"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."activity_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))));

-- Logs an engagement on the records in subjects ([{ type, id }], the first
-- is its main record). attrs: type, title, body, outcome, ownerId, dueAt,
-- doneAt, durationSeconds, externalRef and fields (the extra columns by
-- name). A known externalRef updates instead.
create or replace function "better_supabase"."log_activity"(tenant uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant uuid := log_activity.tenant;
  v_type text := log_activity.attrs ->> 'type';
  v_title text := nullif(trim(log_activity.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_activity.attrs ->> 'ownerId', '')::uuid, auth.uid());
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'activities.write'), false)) then
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ACTIVITY_TITLE_REQUIRED';
  end if;
  if nullif(log_activity.attrs ->> 'audience', '') is not null and not (log_activity.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if log_activity.attrs ? 'restrictedRoles' and jsonb_typeof(log_activity.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if nullif(log_activity.attrs ->> 'category', '') is not null and not (log_activity.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ACTIVITY_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."tenant_id" = v_tenant and x."external_ref" = log_activity.attrs ->> 'externalRef' and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_activity_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_activity.tenant, log_activity.attrs, log_activity.subjects;
    end if;
  end;
  insert into "better_supabase"."activities" ("tenant_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by", "audience", "restricted_roles", "category", "locked_at", "goal_id")
  values (v_tenant, v_type, v_title, log_activity.attrs ->> 'body', log_activity.attrs ->> 'outcome', v_owner, (log_activity.attrs ->> 'dueAt')::timestamptz, (log_activity.attrs ->> 'doneAt')::timestamptz, (log_activity.attrs ->> 'durationSeconds')::integer, log_activity.attrs ->> 'externalRef', auth.uid(), coalesce(nullif(log_activity.attrs ->> 'audience', ''), 'team'), nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(log_activity.attrs -> 'restrictedRoles') = 'array' then log_activity.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}'), nullif(log_activity.attrs ->> 'category', ''), case when v_type = any ('{note,report}'::text[]) then now() + interval '24 hours' end, nullif(log_activity.attrs ->> 'goalId', '')::uuid)
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at", "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."activity_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_activity_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."log_activity"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."log_activity"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys attrs names, and the records when subjects isn't null.
-- The author, the owner and members with engagements.manage may edit.
create or replace function "better_supabase"."update_activity"(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := update_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_title text;
  v_owner uuid;
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type", x."owner_user_id" into v_tenant, v_type, v_previous_owner
  from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if update_activity.attrs ? 'type' and not (update_activity.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
  end if;
  if nullif(update_activity.attrs ->> 'audience', '') is not null and not (update_activity.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if update_activity.attrs ? 'restrictedRoles' and jsonb_typeof(update_activity.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if nullif(update_activity.attrs ->> 'category', '') is not null and not (update_activity.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ACTIVITY_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "better_supabase"."activities" x set
    "type" = coalesce(update_activity.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_activity.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_activity.attrs ? 'body' then update_activity.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_activity.attrs ? 'outcome' then update_activity.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_activity.attrs ? 'externalRef' then update_activity.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_activity.attrs ? 'ownerId' then nullif(update_activity.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_activity.attrs ? 'dueAt' then (update_activity.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_activity.attrs ? 'doneAt' then (update_activity.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_activity.attrs ? 'durationSeconds' then (update_activity.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "audience" = case when update_activity.attrs ? 'audience' then coalesce(nullif(update_activity.attrs ->> 'audience', ''), 'team') else x."audience" end,
    "restricted_roles" = case when update_activity.attrs ? 'restrictedRoles' then nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(update_activity.attrs -> 'restrictedRoles') = 'array' then update_activity.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}') else x."restricted_roles" end,
    "category" = case when update_activity.attrs ? 'category' then nullif(update_activity.attrs ->> 'category', '') else x."category" end,
    "goal_id" = case when update_activity.attrs ? 'goalId' then nullif(update_activity.attrs ->> 'goalId', '')::uuid else x."goal_id" end,
    "locked_at" = case when update_activity.attrs ? 'type' then coalesce(x."locked_at", case when update_activity.attrs ->> 'type' = any ('{note,report}'::text[]) then x."created_at" + interval '24 hours' end) else x."locked_at" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_activity.subjects is not null then
    
  if jsonb_typeof(coalesce(update_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."activity_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."update_activity"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."update_activity"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Marks an engagement done now (done true) or open again.
create or replace function "better_supabase"."complete_activity"(engagement uuid, done boolean, outcome text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := complete_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = complete_activity.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "better_supabase"."activities" x set
    "done_at" = case when complete_activity.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_activity.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if complete_activity.done then
    null;
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."complete_activity"(uuid, boolean, text) from public, anon;
grant execute on function "better_supabase"."complete_activity"(uuid, boolean, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_activity"(engagement uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = delete_activity.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  delete from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_activity"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_activity"(uuid) to authenticated, service_role;

-- A record's engagements the caller can see, newest first: done ones by
-- when they happened, open ones by when they are due. before continues
-- after the last row of the previous page.
create or replace function "better_supabase"."activities_of"(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb) into v_rows
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, coalesce(x."done_at", x."due_at", x."created_at") as at, x."id" as id
    from "better_supabase"."activities" x
    join "better_supabase"."engagement_subjects" k on k."activity_id" = x."id"
    where k."subject_type" = activities_of.subject_type and k."subject_id" = activities_of.subject_id
      and (activities_of.types is null or x."type" = any (activities_of.types))
      and (activities_of.before is null or coalesce(x."done_at", x."due_at", x."created_at") < activities_of.before)
    order by at desc, id desc
    limit least(greatest(coalesce(activities_of.page_size, 50), 1), 200)
  ) p;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."activities_of"(text, text, text[], timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."activities_of"(text, text, text[], timestamptz, integer) to authenticated, service_role;

-- The next open engagement with a due time on a record, earliest first,
-- for a "next step" and an overdue flag; null when none is planned.
create or replace function "better_supabase"."next_activity"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now())
  from "better_supabase"."activities" x
  join "better_supabase"."engagement_subjects" k on k."activity_id" = x."id"
  where k."subject_type" = next_activity.subject_type and k."subject_id" = next_activity.subject_id
    and x."done_at" is null and x."due_at" is not null
  order by x."due_at", x."id"
  limit 1
$$;
revoke execute on function "better_supabase"."next_activity"(text, text) from public, anon;
grant execute on function "better_supabase"."next_activity"(text, text) to authenticated, service_role;

-- A member's open engagements in a tenant, earliest due first: a task list.
create or replace function "better_supabase"."open_activities"(tenant uuid, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.due nulls last, p.id), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, x."due_at" as due, x."id" as id
    from "better_supabase"."activities" x
    where x."tenant_id" = open_activities.tenant
      and x."owner_user_id" = coalesce(open_activities.owner, auth.uid())
      and x."done_at" is null
      and (open_activities.due_before is null or x."due_at" < open_activities.due_before)
    order by x."due_at" nulls last, x."id"
    limit least(greatest(coalesce(open_activities.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."open_activities"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."open_activities"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- Adds an addendum to an engagement the caller can read: a new engagement of
-- the same type, title, audience and records with body, pointing at it
-- through amends_id. A locked note changes this way only.
create or replace function "better_supabase"."amend_activity"(engagement uuid, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from "better_supabase"."activities";
  v_id uuid;
  v_body text := nullif(trim(amend_activity.body), '');
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_from from "better_supabase"."activities" x
  where x."id" = amend_activity.engagement and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = x."id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = x."id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and (x."audience" <> 'restricted' or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or x."owner_user_id" = (select auth.uid()) or x."created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."activity_id" = x."id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", x."restricted_roles"))));
  if v_from."id" is null then
    raise exception 'no such engagement you can read' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'activities.write'), false)) then
    raise exception 'not allowed to amend engagements' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_body is null then
    raise exception 'an addendum needs a body' using errcode = '23502', hint = 'ACTIVITY_BODY_REQUIRED';
  end if;
  insert into "better_supabase"."activities" ("tenant_id", "type", "title", "body", "owner_user_id", "amends_id", "audience", "restricted_roles", "category", "goal_id", "locked_at", "created_by")
  values (v_from."tenant_id", v_from."type", v_from."title", v_body, auth.uid(), v_from."id", v_from."audience", v_from."restricted_roles", v_from."category", v_from."goal_id", case when v_from."type"::text = any ('{note,report}'::text[]) then now() + interval '24 hours' end, auth.uid())
  returning "id" into v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select k."tenant_id", v_id, k."subject_type", k."subject_id", k."position"
  from "better_supabase"."engagement_subjects" k where k."activity_id" = v_from."id";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."amend_activity"(uuid, text) from public, anon;
grant execute on function "better_supabase"."amend_activity"(uuid, text) to authenticated, service_role;

-- Flags an engagement as entered in error with a reason. The row stays, so
-- the record keeps what was written; the flag also locks it. The author, the
-- owner and members with activities.manage may mark it.
create or replace function "better_supabase"."mark_activity_error"(engagement uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := mark_activity_error.engagement;
  v_reason text := nullif(trim(mark_activity_error.reason), '');
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = mark_activity_error.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_reason is null then
    raise exception 'say why the engagement is in error' using errcode = '23502', hint = 'ACTIVITY_REASON_REQUIRED';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."marked_error_at" is not null) then
    raise exception 'the engagement is already marked in error' using errcode = '55000', hint = 'ACTIVITY_ALREADY_MARKED_ERROR';
  end if;
  update "better_supabase"."activities" x set
    "marked_error_at" = now(),
    "marked_error_by" = auth.uid(),
    "marked_error_reason" = v_reason,
    "locked_at" = least(coalesce(x."locked_at", now()), now())
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type"::text into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."mark_activity_error"(uuid, text) from public, anon;
grant execute on function "better_supabase"."mark_activity_error"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."activities";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."activities";
create policy bsb_tenant_scope_select on "better_supabase"."activities" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."activity_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."activities";
create policy bsb_tenant_scope_insert on "better_supabase"."activities" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."activities";
create policy bsb_tenant_scope_update on "better_supabase"."activities" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."activities";
create policy bsb_tenant_scope_delete on "better_supabase"."activities" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."engagement_subjects";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_select on "better_supabase"."engagement_subjects" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_insert on "better_supabase"."engagement_subjects" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_update on "better_supabase"."engagement_subjects" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_delete on "better_supabase"."engagement_subjects" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block-data activities
-- @bsb-hash sha256:3819d4d37eee891adf4bd6627ff0441d632f4d96e372321e5ff3a590794a2b2b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_members"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_members" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."engagement_subjects"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."engagement_subjects" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('activities', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block activities@3 managed
-- @bsb-hash sha256:f109ee4ef9889030d4df015844d4141e8b01029ecee0157ed0eecc8fb538acf1
-- Calls, emails, meetings, notes and tasks logged on one or more registered records, with an owner, a due time and an outcome, a record's timeline, its next step and a member's open tasks.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."activities";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagement_subjects";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Calls, emails, meetings, notes and tasks logged on one or more records.
create table if not exists "better_supabase"."activities" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "type" text not null,
  "title" text not null check (length("title") between 1 and 500),
  "body" text,
  "outcome" text,
  "owner_user_id" uuid,
  "due_at" timestamptz,
  "done_at" timestamptz,
  "duration_seconds" integer check ("duration_seconds" >= 0),
  "external_ref" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "activities_owner_open_idx" on "better_supabase"."activities" ("tenant_id", "owner_user_id", "due_at") where "done_at" is null;
create index if not exists "activities_tenant_created_idx" on "better_supabase"."activities" ("tenant_id", "created_at" desc);
create unique index if not exists "activities_external_ref_idx" on "better_supabase"."activities" ("tenant_id", "external_ref") where "external_ref" is not null;
-- Progress notes: who reads an engagement, when it locks, its addenda and the
-- in-error flag.
alter table "better_supabase"."activities" add column if not exists "audience" text not null default 'team' check ("audience" in ('team', 'subject', 'restricted'));
alter table "better_supabase"."activities" add column if not exists "restricted_roles" text[];
alter table "better_supabase"."activities" add column if not exists "category" text check (length("category") between 1 and 63);
alter table "better_supabase"."activities" add column if not exists "locked_at" timestamptz;
alter table "better_supabase"."activities" add column if not exists "amends_id" uuid references "better_supabase"."activities" ("id") on delete cascade;
alter table "better_supabase"."activities" add column if not exists "goal_id" uuid;
alter table "better_supabase"."activities" add column if not exists "marked_error_at" timestamptz;
alter table "better_supabase"."activities" add column if not exists "marked_error_by" uuid;
alter table "better_supabase"."activities" add column if not exists "marked_error_reason" text check (length("marked_error_reason") between 1 and 2000);
create index if not exists "activities_amends_idx" on "better_supabase"."activities" ("amends_id");
alter table "better_supabase"."activities" enable row level security;
revoke all on "better_supabase"."activities" from public, anon, authenticated;
grant select on "better_supabase"."activities" to authenticated;
grant all on "better_supabase"."activities" to service_role;
create table if not exists "better_supabase"."engagement_subjects" (
  "tenant_id" uuid not null,
  "activity_id" uuid not null references "better_supabase"."activities" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "position" integer not null default 1,
  primary key ("activity_id", "subject_type", "subject_id")
);
create index if not exists engagement_subjects_subject_idx on "better_supabase"."engagement_subjects" ("subject_type", "subject_id");
alter table "better_supabase"."engagement_subjects" enable row level security;
revoke all on "better_supabase"."engagement_subjects" from public, anon, authenticated;
grant select on "better_supabase"."engagement_subjects" to authenticated;
grant all on "better_supabase"."engagement_subjects" to service_role;
-- Whether the caller reaches a subject engagement as a guest of one of its
-- records. Reads past the policies, for the read policies only.
create or replace function "better_supabase"."engagement_guest_readable"(engagement uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."activities" x
    join "better_supabase"."engagement_subjects" k on k."activity_id" = x."id"
    where x."id" = engagement_guest_readable.engagement
      and x."audience" = 'subject'
      and ((k."tenant_id")::text, (k."subject_type")::text, (k."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)
  )
$$;
revoke execute on function "better_supabase"."engagement_guest_readable"(uuid) from public, anon;
grant execute on function "better_supabase"."engagement_guest_readable"(uuid) to authenticated, service_role;
-- A link is visible when its record is; an engagement when one of its
-- records is, or it has none. A guest of a record reads its subject notes.
drop policy if exists engagement_subjects_read on "better_supabase"."engagement_subjects";
create policy engagement_subjects_read on "better_supabase"."engagement_subjects"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read')) or ((("tenant_id")::text, ("subject_type")::text, ("subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) and "better_supabase"."engagement_guest_readable"("activity_id")));
drop policy if exists activities_read on "better_supabase"."activities";
create policy activities_read on "better_supabase"."activities"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."activity_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles")))) or ("audience" = 'subject' and "better_supabase"."engagement_guest_readable"("id")));

-- Logs an engagement on the records in subjects ([{ type, id }], the first
-- is its main record). attrs: type, title, body, outcome, ownerId, dueAt,
-- doneAt, durationSeconds, externalRef and fields (the extra columns by
-- name). A known externalRef updates instead.
create or replace function "better_supabase"."log_activity"(tenant uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant uuid := log_activity.tenant;
  v_type text := log_activity.attrs ->> 'type';
  v_title text := nullif(trim(log_activity.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_activity.attrs ->> 'ownerId', '')::uuid, auth.uid());
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'activities.write'), false)) then
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ACTIVITY_TITLE_REQUIRED';
  end if;
  if nullif(log_activity.attrs ->> 'audience', '') is not null and not (log_activity.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if log_activity.attrs ? 'restrictedRoles' and jsonb_typeof(log_activity.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if nullif(log_activity.attrs ->> 'category', '') is not null and not (log_activity.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ACTIVITY_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."tenant_id" = v_tenant and x."external_ref" = log_activity.attrs ->> 'externalRef' and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_activity_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_activity.tenant, log_activity.attrs, log_activity.subjects;
    end if;
  end;
  insert into "better_supabase"."activities" ("tenant_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by", "audience", "restricted_roles", "category", "locked_at", "goal_id")
  values (v_tenant, v_type, v_title, log_activity.attrs ->> 'body', log_activity.attrs ->> 'outcome', v_owner, (log_activity.attrs ->> 'dueAt')::timestamptz, (log_activity.attrs ->> 'doneAt')::timestamptz, (log_activity.attrs ->> 'durationSeconds')::integer, log_activity.attrs ->> 'externalRef', auth.uid(), coalesce(nullif(log_activity.attrs ->> 'audience', ''), 'team'), nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(log_activity.attrs -> 'restrictedRoles') = 'array' then log_activity.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}'), nullif(log_activity.attrs ->> 'category', ''), case when v_type = any ('{note,report}'::text[]) then now() + interval '24 hours' end, nullif(log_activity.attrs ->> 'goalId', '')::uuid)
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at", "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."activity_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.logged', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'engagement.assigned',
      'tenant', v_tenant,
      'actor', auth.uid(),
      'subject_type', v_first ->> 'type',
      'subject_id', v_first ->> 'id',
      'summary', v_title,
      'recipients', jsonb_build_array(v_owner),
      'watchers', false,
      'key', 'engagement.assigned:' || v_id::text || ':' || v_owner::text,
      'data', jsonb_build_object('engagementId', v_id)
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_activity_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."log_activity"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."log_activity"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys attrs names, and the records when subjects isn't null.
-- The author, the owner and members with engagements.manage may edit.
create or replace function "better_supabase"."update_activity"(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := update_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_title text;
  v_owner uuid;
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type", x."owner_user_id" into v_tenant, v_type, v_previous_owner
  from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if update_activity.attrs ? 'type' and not (update_activity.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
  end if;
  if nullif(update_activity.attrs ->> 'audience', '') is not null and not (update_activity.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if update_activity.attrs ? 'restrictedRoles' and jsonb_typeof(update_activity.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if nullif(update_activity.attrs ->> 'category', '') is not null and not (update_activity.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ACTIVITY_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "better_supabase"."activities" x set
    "type" = coalesce(update_activity.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_activity.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_activity.attrs ? 'body' then update_activity.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_activity.attrs ? 'outcome' then update_activity.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_activity.attrs ? 'externalRef' then update_activity.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_activity.attrs ? 'ownerId' then nullif(update_activity.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_activity.attrs ? 'dueAt' then (update_activity.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_activity.attrs ? 'doneAt' then (update_activity.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_activity.attrs ? 'durationSeconds' then (update_activity.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "audience" = case when update_activity.attrs ? 'audience' then coalesce(nullif(update_activity.attrs ->> 'audience', ''), 'team') else x."audience" end,
    "restricted_roles" = case when update_activity.attrs ? 'restrictedRoles' then nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(update_activity.attrs -> 'restrictedRoles') = 'array' then update_activity.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}') else x."restricted_roles" end,
    "category" = case when update_activity.attrs ? 'category' then nullif(update_activity.attrs ->> 'category', '') else x."category" end,
    "goal_id" = case when update_activity.attrs ? 'goalId' then nullif(update_activity.attrs ->> 'goalId', '')::uuid else x."goal_id" end,
    "locked_at" = case when update_activity.attrs ? 'type' then coalesce(x."locked_at", case when update_activity.attrs ->> 'type' = any ('{note,report}'::text[]) then x."created_at" + interval '24 hours' end) else x."locked_at" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_activity.subjects is not null then
    
  if jsonb_typeof(coalesce(update_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."activity_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  perform "better_supabase".emit_event('activity.updated', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'engagement.assigned',
      'tenant', v_tenant,
      'actor', auth.uid(),
      'subject_type', v_first ->> 'type',
      'subject_id', v_first ->> 'id',
      'summary', v_title,
      'recipients', jsonb_build_array(v_owner),
      'watchers', false,
      'key', 'engagement.assigned:' || v_id::text || ':' || v_owner::text,
      'data', jsonb_build_object('engagementId', v_id)
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."update_activity"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."update_activity"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Marks an engagement done now (done true) or open again.
create or replace function "better_supabase"."complete_activity"(engagement uuid, done boolean, outcome text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := complete_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = complete_activity.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "better_supabase"."activities" x set
    "done_at" = case when complete_activity.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_activity.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if complete_activity.done then
    perform "better_supabase".emit_event('activity.completed', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."complete_activity"(uuid, boolean, text) from public, anon;
grant execute on function "better_supabase"."complete_activity"(uuid, boolean, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_activity"(engagement uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = delete_activity.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  delete from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  perform "better_supabase".emit_event('activity.deleted', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_activity"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_activity"(uuid) to authenticated, service_role;

-- A record's engagements the caller can see, newest first: done ones by
-- when they happened, open ones by when they are due. before continues
-- after the last row of the previous page.
create or replace function "better_supabase"."activities_of"(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb) into v_rows
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, coalesce(x."done_at", x."due_at", x."created_at") as at, x."id" as id
    from "better_supabase"."activities" x
    join "better_supabase"."engagement_subjects" k on k."activity_id" = x."id"
    where k."subject_type" = activities_of.subject_type and k."subject_id" = activities_of.subject_id
      and (activities_of.types is null or x."type" = any (activities_of.types))
      and (activities_of.before is null or coalesce(x."done_at", x."due_at", x."created_at") < activities_of.before)
    order by at desc, id desc
    limit least(greatest(coalesce(activities_of.page_size, 50), 1), 200)
  ) p;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."activities_of"(text, text, text[], timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."activities_of"(text, text, text[], timestamptz, integer) to authenticated, service_role;

-- The next open engagement with a due time on a record, earliest first,
-- for a "next step" and an overdue flag; null when none is planned.
create or replace function "better_supabase"."next_activity"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now())
  from "better_supabase"."activities" x
  join "better_supabase"."engagement_subjects" k on k."activity_id" = x."id"
  where k."subject_type" = next_activity.subject_type and k."subject_id" = next_activity.subject_id
    and x."done_at" is null and x."due_at" is not null
  order by x."due_at", x."id"
  limit 1
$$;
revoke execute on function "better_supabase"."next_activity"(text, text) from public, anon;
grant execute on function "better_supabase"."next_activity"(text, text) to authenticated, service_role;

-- A member's open engagements in a tenant, earliest due first: a task list.
create or replace function "better_supabase"."open_activities"(tenant uuid, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.due nulls last, p.id), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, x."due_at" as due, x."id" as id
    from "better_supabase"."activities" x
    where x."tenant_id" = open_activities.tenant
      and x."owner_user_id" = coalesce(open_activities.owner, auth.uid())
      and x."done_at" is null
      and (open_activities.due_before is null or x."due_at" < open_activities.due_before)
    order by x."due_at" nulls last, x."id"
    limit least(greatest(coalesce(open_activities.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."open_activities"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."open_activities"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- Adds an addendum to an engagement the caller can read: a new engagement of
-- the same type, title, audience and records with body, pointing at it
-- through amends_id. A locked note changes this way only.
create or replace function "better_supabase"."amend_activity"(engagement uuid, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from "better_supabase"."activities";
  v_id uuid;
  v_body text := nullif(trim(amend_activity.body), '');
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_from from "better_supabase"."activities" x
  where x."id" = amend_activity.engagement and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = x."id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = x."id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and (x."audience" <> 'restricted' or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or x."owner_user_id" = (select auth.uid()) or x."created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."activity_id" = x."id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", x."restricted_roles"))));
  if v_from."id" is null then
    raise exception 'no such engagement you can read' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'activities.write'), false)) then
    raise exception 'not allowed to amend engagements' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_body is null then
    raise exception 'an addendum needs a body' using errcode = '23502', hint = 'ACTIVITY_BODY_REQUIRED';
  end if;
  insert into "better_supabase"."activities" ("tenant_id", "type", "title", "body", "owner_user_id", "amends_id", "audience", "restricted_roles", "category", "goal_id", "locked_at", "created_by")
  values (v_from."tenant_id", v_from."type", v_from."title", v_body, auth.uid(), v_from."id", v_from."audience", v_from."restricted_roles", v_from."category", v_from."goal_id", case when v_from."type"::text = any ('{note,report}'::text[]) then now() + interval '24 hours' end, auth.uid())
  returning "id" into v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select k."tenant_id", v_id, k."subject_type", k."subject_id", k."position"
  from "better_supabase"."engagement_subjects" k where k."activity_id" = v_from."id";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.amended', jsonb_build_object('organizationId', v_from."tenant_id", 'engagementId', v_id, 'type', v_from."type"::text, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'amendsId', v_from."id"), 'engagements/' || v_id::text, (v_from."tenant_id"::text)::text, null, 'better-supabase/activities');
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."amend_activity"(uuid, text) from public, anon;
grant execute on function "better_supabase"."amend_activity"(uuid, text) to authenticated, service_role;

-- Flags an engagement as entered in error with a reason. The row stays, so
-- the record keeps what was written; the flag also locks it. The author, the
-- owner and members with activities.manage may mark it.
create or replace function "better_supabase"."mark_activity_error"(engagement uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := mark_activity_error.engagement;
  v_reason text := nullif(trim(mark_activity_error.reason), '');
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = mark_activity_error.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_reason is null then
    raise exception 'say why the engagement is in error' using errcode = '23502', hint = 'ACTIVITY_REASON_REQUIRED';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."marked_error_at" is not null) then
    raise exception 'the engagement is already marked in error' using errcode = '55000', hint = 'ACTIVITY_ALREADY_MARKED_ERROR';
  end if;
  update "better_supabase"."activities" x set
    "marked_error_at" = now(),
    "marked_error_by" = auth.uid(),
    "marked_error_reason" = v_reason,
    "locked_at" = least(coalesce(x."locked_at", now()), now())
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type"::text into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  perform "better_supabase".emit_event('activity.error_marked', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'reason', v_reason), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."mark_activity_error"(uuid, text) from public, anon;
grant execute on function "better_supabase"."mark_activity_error"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."activities";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."activities";
create policy bsb_tenant_scope_select on "better_supabase"."activities" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."activity_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles")))) or ("audience" = 'subject' and "better_supabase"."engagement_guest_readable"("id")))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."activities";
create policy bsb_tenant_scope_insert on "better_supabase"."activities" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."activities";
create policy bsb_tenant_scope_update on "better_supabase"."activities" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."activities";
create policy bsb_tenant_scope_delete on "better_supabase"."activities" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."engagement_subjects";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_select on "better_supabase"."engagement_subjects" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read')) or ((("tenant_id")::text, ("subject_type")::text, ("subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) and "better_supabase"."engagement_guest_readable"("activity_id")))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_insert on "better_supabase"."engagement_subjects" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_update on "better_supabase"."engagement_subjects" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_delete on "better_supabase"."engagement_subjects" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block-data activities
-- @bsb-hash sha256:fd8202f1939e254dd7ac2d2da32501e75980cb49c71d54280875d5a1e6ff4ef3
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."notification_events"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."notification_events" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."notification_subscriptions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."notification_subscriptions" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."incoming_webhooks"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."incoming_webhooks" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."guest_grants"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."guest_grants" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."attachments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."attachments" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."data_exports"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."data_exports" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."enrollments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."enrollments" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."workflow_runs"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."workflow_runs" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."workflow_start_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."workflow_start_requests" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."knowledge_documents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."knowledge_documents" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."memories"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."memories" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."taggings"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."taggings" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."status_history"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."status_history" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."status_stages"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."status_stages" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_lifecycles"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_lifecycles" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."field_values"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."field_values" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."share_links"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."share_links" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_views"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_views" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_user_state"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_user_state" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."recurrence_rules"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."recurrence_rules" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reminders"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reminders" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."import_records"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."import_records" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_members"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_members" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."relations"') and attname = 'source_type' and not attisdropped) then update "better_supabase"."relations" set "source_type" = 'activity' where "source_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."relations"') and attname = 'target_type' and not attisdropped) then update "better_supabase"."relations" set "target_type" = 'activity' where "target_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."bulk_runs"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."bulk_runs" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."search_documents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."search_documents" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."calendar_events"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."calendar_events" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."calendar_attendees"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."calendar_attendees" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."versions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."versions" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."trash_items"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."trash_items" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reactions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reactions" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reaction_scores"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reaction_scores" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."approval_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."approval_requests" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."approval_policies"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."approval_policies" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."access_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."access_requests" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."documents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."documents" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."form_submissions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."form_submissions" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."signature_requests"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."signature_requests" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."time_entries"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."time_entries" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."template_applications"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."template_applications" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipelines"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipelines" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."pipeline_stage_history"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."pipeline_stage_history" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."engagement_subjects"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."engagement_subjects" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."sla_policies"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."sla_policies" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."sla_clocks"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."sla_clocks" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_collections"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_collections" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_collection_entries"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_collection_entries" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."collection_favorites"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."collection_favorites" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."saved_items"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."saved_items" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."moderation_items"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."moderation_items" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."reviews"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."reviews" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."review_stats"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."review_stats" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."automations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."automations" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."automation_defaults"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."automation_defaults" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."automation_evaluations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."automation_evaluations" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."automation_fields"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."automation_fields" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."score_models"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."score_models" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."scores"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."scores" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."passes"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."passes" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."work_orders"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."work_orders" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."shipments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."shipments" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."conversations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."conversations" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."message_record_mentions"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."message_record_mentions" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."channels"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."channels" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."timeline_entries"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."timeline_entries" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."mail_thread_subjects"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."mail_thread_subjects" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."segments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."segments" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."assignment_queues"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."assignment_queues" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."assignments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."assignments" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."field_changes"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."field_changes" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."lead_score_checks"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."lead_score_checks" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."qualification_requirements"') and attname = 'target_type' and not attisdropped) then update "better_supabase"."qualification_requirements" set "target_type" = 'activity' where "target_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."acknowledgement_assignments"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."acknowledgement_assignments" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."acknowledgements"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."acknowledgements" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."acknowledgement_notices"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."acknowledgement_notices" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."consents"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."consents" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."observations"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."observations" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."medication_orders"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."medication_orders" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."care_plans"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."care_plans" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."bank_matches"') and attname = 'target_type' and not attisdropped) then update "better_supabase"."bank_matches" set "target_type" = 'activity' where "target_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."funding_awards"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."funding_awards" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."funding_deliveries"') and attname = 'source_type' and not attisdropped) then update "better_supabase"."funding_deliveries" set "source_type" = 'activity' where "source_type" = 'engagement'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('activities', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block activities@3 managed
-- @bsb-hash sha256:14f3a78497be0eb211f4cca8cb369379fa6e47945c73cda2c245ba89b0010db4
-- Calls, emails, meetings, notes and tasks logged on one or more registered records, with an owner, a due time and an outcome, a record's timeline, its next step and a member's open tasks.
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
    drop policy if exists bsb_tenant_scope on "app_private"."activities";
    drop policy if exists bsb_tenant_scope_select on "app_private"."activities";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."activities";
    drop policy if exists bsb_tenant_scope_update on "app_private"."activities";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."activities";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_select on "app_private"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_update on "app_private"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."engagement_subjects";
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
-- Calls, emails, meetings, notes and tasks logged on one or more records.
create table if not exists "app_private"."activities" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "type" text not null,
  "title" text not null check (length("title") between 1 and 500),
  "body" text,
  "outcome" text,
  "owner_user_id" uuid,
  "due_at" timestamptz,
  "done_at" timestamptz,
  "duration_seconds" integer check ("duration_seconds" >= 0),
  "external_ref" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "activities_owner_open_idx" on "app_private"."activities" ("tenant_id", "owner_user_id", "due_at") where "done_at" is null;
create index if not exists "activities_tenant_created_idx" on "app_private"."activities" ("tenant_id", "created_at" desc);
create unique index if not exists "activities_external_ref_idx" on "app_private"."activities" ("tenant_id", "external_ref") where "external_ref" is not null;
-- Progress notes: who reads an engagement, when it locks, its addenda and the
-- in-error flag.
alter table "app_private"."activities" add column if not exists "audience" text not null default 'team' check ("audience" in ('team', 'subject', 'restricted'));
alter table "app_private"."activities" add column if not exists "restricted_roles" text[];
alter table "app_private"."activities" add column if not exists "category" text check (length("category") between 1 and 63);
alter table "app_private"."activities" add column if not exists "locked_at" timestamptz;
alter table "app_private"."activities" add column if not exists "amends_id" uuid references "app_private"."activities" ("id") on delete cascade;
alter table "app_private"."activities" add column if not exists "goal_id" uuid;
alter table "app_private"."activities" add column if not exists "marked_error_at" timestamptz;
alter table "app_private"."activities" add column if not exists "marked_error_by" uuid;
alter table "app_private"."activities" add column if not exists "marked_error_reason" text check (length("marked_error_reason") between 1 and 2000);
create index if not exists "activities_amends_idx" on "app_private"."activities" ("amends_id");
alter table "app_private"."activities" enable row level security;
revoke all on "app_private"."activities" from public, anon, authenticated;
grant select on "app_private"."activities" to authenticated;
grant all on "app_private"."activities" to service_role;
create table if not exists "app_private"."engagement_subjects" (
  "tenant_id" uuid not null,
  "activity_id" uuid not null references "app_private"."activities" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "position" integer not null default 1,
  primary key ("activity_id", "subject_type", "subject_id")
);
create index if not exists engagement_subjects_subject_idx on "app_private"."engagement_subjects" ("subject_type", "subject_id");
alter table "app_private"."engagement_subjects" enable row level security;
revoke all on "app_private"."engagement_subjects" from public, anon, authenticated;
grant select on "app_private"."engagement_subjects" to authenticated;
grant all on "app_private"."engagement_subjects" to service_role;
-- A link is visible when its record is; an engagement when one of its
-- records is, or it has none. A guest of a record reads its subject notes.
drop policy if exists engagement_subjects_read on "app_private"."engagement_subjects";
create policy engagement_subjects_read on "app_private"."engagement_subjects"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));
drop policy if exists activities_read on "app_private"."activities";
create policy activities_read on "app_private"."activities"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "app_private"."engagement_subjects" lx where lx."activity_id" = "id")
  or exists (select 1 from "app_private"."engagement_subjects" lx where lx."activity_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "app_private"."engagement_subjects" nx where nx."activity_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))));

-- Logs an engagement on the records in subjects ([{ type, id }], the first
-- is its main record). attrs: type, title, body, outcome, ownerId, dueAt,
-- doneAt, durationSeconds, externalRef and fields (the extra columns by
-- name). A known externalRef updates instead.
create or replace function "app_private"."log_activity"(tenant uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant uuid := log_activity.tenant;
  v_type text := log_activity.attrs ->> 'type';
  v_title text := nullif(trim(log_activity.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_activity.attrs ->> 'ownerId', '')::uuid, auth.uid());
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'activities.write'), false)) then
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ACTIVITY_TITLE_REQUIRED';
  end if;
  if nullif(log_activity.attrs ->> 'audience', '') is not null and not (log_activity.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if log_activity.attrs ? 'restrictedRoles' and jsonb_typeof(log_activity.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if nullif(log_activity.attrs ->> 'category', '') is not null and not (log_activity.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ACTIVITY_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "app_private"."activities" x where x."tenant_id" = v_tenant and x."external_ref" = log_activity.attrs ->> 'externalRef' and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_activity_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_activity.tenant, log_activity.attrs, log_activity.subjects;
    end if;
  end;
  insert into "app_private"."activities" ("tenant_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by", "audience", "restricted_roles", "category", "locked_at", "goal_id")
  values (v_tenant, v_type, v_title, log_activity.attrs ->> 'body', log_activity.attrs ->> 'outcome', v_owner, (log_activity.attrs ->> 'dueAt')::timestamptz, (log_activity.attrs ->> 'doneAt')::timestamptz, (log_activity.attrs ->> 'durationSeconds')::integer, log_activity.attrs ->> 'externalRef', auth.uid(), coalesce(nullif(log_activity.attrs ->> 'audience', ''), 'team'), nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(log_activity.attrs -> 'restrictedRoles') = 'array' then log_activity.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}'), nullif(log_activity.attrs ->> 'category', ''), case when v_type = any ('{note,report}'::text[]) then now() + interval '24 hours' end, nullif(log_activity.attrs ->> 'goalId', '')::uuid)
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at", "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "app_private"."engagement_subjects" x where x."activity_id" = v_id;
  insert into "app_private"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_activity_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "app_private"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."log_activity"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "app_private"."log_activity"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys attrs names, and the records when subjects isn't null.
-- The author, the owner and members with engagements.manage may edit.
create or replace function "app_private"."update_activity"(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := update_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_title text;
  v_owner uuid;
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type", x."owner_user_id" into v_tenant, v_type, v_previous_owner
  from "app_private"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if update_activity.attrs ? 'type' and not (update_activity.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
  end if;
  if nullif(update_activity.attrs ->> 'audience', '') is not null and not (update_activity.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if update_activity.attrs ? 'restrictedRoles' and jsonb_typeof(update_activity.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if nullif(update_activity.attrs ->> 'category', '') is not null and not (update_activity.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ACTIVITY_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "app_private"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "app_private"."activities" x set
    "type" = coalesce(update_activity.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_activity.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_activity.attrs ? 'body' then update_activity.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_activity.attrs ? 'outcome' then update_activity.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_activity.attrs ? 'externalRef' then update_activity.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_activity.attrs ? 'ownerId' then nullif(update_activity.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_activity.attrs ? 'dueAt' then (update_activity.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_activity.attrs ? 'doneAt' then (update_activity.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_activity.attrs ? 'durationSeconds' then (update_activity.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "audience" = case when update_activity.attrs ? 'audience' then coalesce(nullif(update_activity.attrs ->> 'audience', ''), 'team') else x."audience" end,
    "restricted_roles" = case when update_activity.attrs ? 'restrictedRoles' then nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(update_activity.attrs -> 'restrictedRoles') = 'array' then update_activity.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}') else x."restricted_roles" end,
    "category" = case when update_activity.attrs ? 'category' then nullif(update_activity.attrs ->> 'category', '') else x."category" end,
    "goal_id" = case when update_activity.attrs ? 'goalId' then nullif(update_activity.attrs ->> 'goalId', '')::uuid else x."goal_id" end,
    "locked_at" = case when update_activity.attrs ? 'type' then coalesce(x."locked_at", case when update_activity.attrs ->> 'type' = any ('{note,report}'::text[]) then x."created_at" + interval '24 hours' end) else x."locked_at" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_activity.subjects is not null then
    
  if jsonb_typeof(coalesce(update_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "app_private"."engagement_subjects" x where x."activity_id" = v_id;
  insert into "app_private"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "app_private"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."update_activity"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "app_private"."update_activity"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Marks an engagement done now (done true) or open again.
create or replace function "app_private"."complete_activity"(engagement uuid, done boolean, outcome text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := complete_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."activity_id" = complete_activity.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "app_private"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "app_private"."activities" x set
    "done_at" = case when complete_activity.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_activity.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if complete_activity.done then
    null;
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "app_private"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."complete_activity"(uuid, boolean, text) from public, anon;
grant execute on function "app_private"."complete_activity"(uuid, boolean, text) to authenticated, service_role;

create or replace function "app_private"."delete_activity"(engagement uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."activity_id" = delete_activity.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "app_private"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  delete from "app_private"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_activity"(uuid) from public, anon;
grant execute on function "app_private"."delete_activity"(uuid) to authenticated, service_role;

-- A record's engagements the caller can see, newest first: done ones by
-- when they happened, open ones by when they are due. before continues
-- after the last row of the previous page.
create or replace function "app_private"."activities_of"(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb) into v_rows
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, coalesce(x."done_at", x."due_at", x."created_at") as at, x."id" as id
    from "app_private"."activities" x
    join "app_private"."engagement_subjects" k on k."activity_id" = x."id"
    where k."subject_type" = activities_of.subject_type and k."subject_id" = activities_of.subject_id
      and (activities_of.types is null or x."type" = any (activities_of.types))
      and (activities_of.before is null or coalesce(x."done_at", x."due_at", x."created_at") < activities_of.before)
    order by at desc, id desc
    limit least(greatest(coalesce(activities_of.page_size, 50), 1), 200)
  ) p;
  return v_rows;
end;
$$;
revoke execute on function "app_private"."activities_of"(text, text, text[], timestamptz, integer) from public, anon;
grant execute on function "app_private"."activities_of"(text, text, text[], timestamptz, integer) to authenticated, service_role;

-- The next open engagement with a due time on a record, earliest first,
-- for a "next step" and an overdue flag; null when none is planned.
create or replace function "app_private"."next_activity"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now())
  from "app_private"."activities" x
  join "app_private"."engagement_subjects" k on k."activity_id" = x."id"
  where k."subject_type" = next_activity.subject_type and k."subject_id" = next_activity.subject_id
    and x."done_at" is null and x."due_at" is not null
  order by x."due_at", x."id"
  limit 1
$$;
revoke execute on function "app_private"."next_activity"(text, text) from public, anon;
grant execute on function "app_private"."next_activity"(text, text) to authenticated, service_role;

-- A member's open engagements in a tenant, earliest due first: a task list.
create or replace function "app_private"."open_activities"(tenant uuid, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.due nulls last, p.id), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, x."due_at" as due, x."id" as id
    from "app_private"."activities" x
    where x."tenant_id" = open_activities.tenant
      and x."owner_user_id" = coalesce(open_activities.owner, auth.uid())
      and x."done_at" is null
      and (open_activities.due_before is null or x."due_at" < open_activities.due_before)
    order by x."due_at" nulls last, x."id"
    limit least(greatest(coalesce(open_activities.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "app_private"."open_activities"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "app_private"."open_activities"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- Adds an addendum to an engagement the caller can read: a new engagement of
-- the same type, title, audience and records with body, pointing at it
-- through amends_id. A locked note changes this way only.
create or replace function "app_private"."amend_activity"(engagement uuid, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from "app_private"."activities";
  v_id uuid;
  v_body text := nullif(trim(amend_activity.body), '');
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_from from "app_private"."activities" x
  where x."id" = amend_activity.engagement and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "app_private"."engagement_subjects" lx where lx."activity_id" = x."id")
  or exists (select 1 from "app_private"."engagement_subjects" lx where lx."activity_id" = x."id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and (x."audience" <> 'restricted' or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or x."owner_user_id" = (select auth.uid()) or x."created_by" = (select auth.uid()) or exists (select 1 from "app_private"."engagement_subjects" nx where nx."activity_id" = x."id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", x."restricted_roles"))));
  if v_from."id" is null then
    raise exception 'no such engagement you can read' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'activities.write'), false)) then
    raise exception 'not allowed to amend engagements' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_body is null then
    raise exception 'an addendum needs a body' using errcode = '23502', hint = 'ACTIVITY_BODY_REQUIRED';
  end if;
  insert into "app_private"."activities" ("tenant_id", "type", "title", "body", "owner_user_id", "amends_id", "audience", "restricted_roles", "category", "goal_id", "locked_at", "created_by")
  values (v_from."tenant_id", v_from."type", v_from."title", v_body, auth.uid(), v_from."id", v_from."audience", v_from."restricted_roles", v_from."category", v_from."goal_id", case when v_from."type"::text = any ('{note,report}'::text[]) then now() + interval '24 hours' end, auth.uid())
  returning "id" into v_id;
  insert into "app_private"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select k."tenant_id", v_id, k."subject_type", k."subject_id", k."position"
  from "app_private"."engagement_subjects" k where k."activity_id" = v_from."id";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "app_private"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."amend_activity"(uuid, text) from public, anon;
grant execute on function "app_private"."amend_activity"(uuid, text) to authenticated, service_role;

-- Flags an engagement as entered in error with a reason. The row stays, so
-- the record keeps what was written; the flag also locks it. The author, the
-- owner and members with activities.manage may mark it.
create or replace function "app_private"."mark_activity_error"(engagement uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := mark_activity_error.engagement;
  v_reason text := nullif(trim(mark_activity_error.reason), '');
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."activity_id" = mark_activity_error.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_reason is null then
    raise exception 'say why the engagement is in error' using errcode = '23502', hint = 'ACTIVITY_REASON_REQUIRED';
  end if;
  if exists (select 1 from "app_private"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."marked_error_at" is not null) then
    raise exception 'the engagement is already marked in error' using errcode = '55000', hint = 'ACTIVITY_ALREADY_MARKED_ERROR';
  end if;
  update "app_private"."activities" x set
    "marked_error_at" = now(),
    "marked_error_by" = auth.uid(),
    "marked_error_reason" = v_reason,
    "locked_at" = least(coalesce(x."locked_at", now()), now())
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type"::text into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "app_private"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."mark_activity_error"(uuid, text) from public, anon;
grant execute on function "app_private"."mark_activity_error"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."activities";
drop policy if exists bsb_tenant_scope_select on "app_private"."activities";
create policy bsb_tenant_scope_select on "app_private"."activities" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "app_private"."engagement_subjects" lx where lx."activity_id" = "id")
  or exists (select 1 from "app_private"."engagement_subjects" lx where lx."activity_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "app_private"."engagement_subjects" nx where nx."activity_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."activities";
create policy bsb_tenant_scope_insert on "app_private"."activities" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."activities";
create policy bsb_tenant_scope_update on "app_private"."activities" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."activities";
create policy bsb_tenant_scope_delete on "app_private"."activities" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."engagement_subjects";
drop policy if exists bsb_tenant_scope_select on "app_private"."engagement_subjects";
create policy bsb_tenant_scope_select on "app_private"."engagement_subjects" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."engagement_subjects";
create policy bsb_tenant_scope_insert on "app_private"."engagement_subjects" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."engagement_subjects";
create policy bsb_tenant_scope_update on "app_private"."engagement_subjects" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."engagement_subjects";
create policy bsb_tenant_scope_delete on "app_private"."engagement_subjects" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block-data activities
-- @bsb-hash sha256:582adc4a2c0ae42f14e88256e417b9c30c280b7b6b56dbd24c30446c0170b36b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_members"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_members" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"app_private"."engagement_subjects"') and attname = 'subject_type' and not attisdropped) then update "app_private"."engagement_subjects" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('activities', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block activities@3 managed
-- @bsb-hash sha256:677f3e90db825a473af45d532ea418c227903dace31786d6fc0782c84a351ae7
-- Calls, emails, meetings, notes and tasks logged on one or more registered records, with an owner, a due time and an outcome, a record's timeline, its next step and a member's open tasks.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."activities";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagement_subjects";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Calls, emails, meetings, notes and tasks logged on one or more records.
create table if not exists "better_supabase"."activities" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "type" text not null,
  "title" text not null check (length("title") between 1 and 500),
  "body" text,
  "outcome" text,
  "owner_user_id" uuid,
  "due_at" timestamptz,
  "done_at" timestamptz,
  "duration_seconds" integer check ("duration_seconds" >= 0),
  "external_ref" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "activities_owner_open_idx" on "better_supabase"."activities" ("tenant_id", "owner_user_id", "due_at") where "done_at" is null;
create index if not exists "activities_tenant_created_idx" on "better_supabase"."activities" ("tenant_id", "created_at" desc);
create unique index if not exists "activities_external_ref_idx" on "better_supabase"."activities" ("tenant_id", "external_ref") where "external_ref" is not null;
-- Progress notes: who reads an engagement, when it locks, its addenda and the
-- in-error flag.
alter table "better_supabase"."activities" add column if not exists "audience" text not null default 'team' check ("audience" in ('team', 'subject', 'restricted'));
alter table "better_supabase"."activities" add column if not exists "restricted_roles" text[];
alter table "better_supabase"."activities" add column if not exists "category" text check (length("category") between 1 and 63);
alter table "better_supabase"."activities" add column if not exists "locked_at" timestamptz;
alter table "better_supabase"."activities" add column if not exists "amends_id" uuid references "better_supabase"."activities" ("id") on delete cascade;
alter table "better_supabase"."activities" add column if not exists "goal_id" uuid;
alter table "better_supabase"."activities" add column if not exists "marked_error_at" timestamptz;
alter table "better_supabase"."activities" add column if not exists "marked_error_by" uuid;
alter table "better_supabase"."activities" add column if not exists "marked_error_reason" text check (length("marked_error_reason") between 1 and 2000);
create index if not exists "activities_amends_idx" on "better_supabase"."activities" ("amends_id");
alter table "better_supabase"."activities" enable row level security;
revoke all on "better_supabase"."activities" from public, anon, authenticated;
grant select on "better_supabase"."activities" to authenticated;
grant all on "better_supabase"."activities" to service_role;
create table if not exists "better_supabase"."engagement_subjects" (
  "tenant_id" uuid not null,
  "activity_id" uuid not null references "better_supabase"."activities" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "position" integer not null default 1,
  primary key ("activity_id", "subject_type", "subject_id")
);
create index if not exists engagement_subjects_subject_idx on "better_supabase"."engagement_subjects" ("subject_type", "subject_id");
alter table "better_supabase"."engagement_subjects" enable row level security;
revoke all on "better_supabase"."engagement_subjects" from public, anon, authenticated;
grant select on "better_supabase"."engagement_subjects" to authenticated;
grant all on "better_supabase"."engagement_subjects" to service_role;
-- A link is visible when its record is; an engagement when one of its
-- records is, or it has none. A guest of a record reads its subject notes.
drop policy if exists engagement_subjects_read on "better_supabase"."engagement_subjects";
create policy engagement_subjects_read on "better_supabase"."engagement_subjects"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));
drop policy if exists activities_read on "better_supabase"."activities";
create policy activities_read on "better_supabase"."activities"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."activity_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))));

-- Logs an engagement on the records in subjects ([{ type, id }], the first
-- is its main record). attrs: type, title, body, outcome, ownerId, dueAt,
-- doneAt, durationSeconds, externalRef and fields (the extra columns by
-- name). A known externalRef updates instead.
create or replace function "better_supabase"."log_activity"(tenant uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant uuid := log_activity.tenant;
  v_type text := log_activity.attrs ->> 'type';
  v_title text := nullif(trim(log_activity.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_activity.attrs ->> 'ownerId', '')::uuid, auth.uid());
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'activities.write'), false)) then
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ACTIVITY_TITLE_REQUIRED';
  end if;
  if nullif(log_activity.attrs ->> 'audience', '') is not null and not (log_activity.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if log_activity.attrs ? 'restrictedRoles' and jsonb_typeof(log_activity.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if nullif(log_activity.attrs ->> 'category', '') is not null and not (log_activity.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ACTIVITY_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."tenant_id" = v_tenant and x."external_ref" = log_activity.attrs ->> 'externalRef' and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_activity_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_activity.tenant, log_activity.attrs, log_activity.subjects;
    end if;
  end;
  insert into "better_supabase"."activities" ("tenant_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by", "audience", "restricted_roles", "category", "locked_at", "goal_id")
  values (v_tenant, v_type, v_title, log_activity.attrs ->> 'body', log_activity.attrs ->> 'outcome', v_owner, (log_activity.attrs ->> 'dueAt')::timestamptz, (log_activity.attrs ->> 'doneAt')::timestamptz, (log_activity.attrs ->> 'durationSeconds')::integer, log_activity.attrs ->> 'externalRef', auth.uid(), coalesce(nullif(log_activity.attrs ->> 'audience', ''), 'team'), nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(log_activity.attrs -> 'restrictedRoles') = 'array' then log_activity.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}'), nullif(log_activity.attrs ->> 'category', ''), case when v_type = any ('{note,report}'::text[]) then now() + interval '24 hours' end, nullif(log_activity.attrs ->> 'goalId', '')::uuid)
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at", "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."activity_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_activity_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."log_activity"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."log_activity"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys attrs names, and the records when subjects isn't null.
-- The author, the owner and members with engagements.manage may edit.
create or replace function "better_supabase"."update_activity"(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := update_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_title text;
  v_owner uuid;
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type", x."owner_user_id" into v_tenant, v_type, v_previous_owner
  from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if update_activity.attrs ? 'type' and not (update_activity.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
  end if;
  if nullif(update_activity.attrs ->> 'audience', '') is not null and not (update_activity.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if update_activity.attrs ? 'restrictedRoles' and jsonb_typeof(update_activity.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if nullif(update_activity.attrs ->> 'category', '') is not null and not (update_activity.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ACTIVITY_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "better_supabase"."activities" x set
    "type" = coalesce(update_activity.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_activity.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_activity.attrs ? 'body' then update_activity.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_activity.attrs ? 'outcome' then update_activity.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_activity.attrs ? 'externalRef' then update_activity.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_activity.attrs ? 'ownerId' then nullif(update_activity.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_activity.attrs ? 'dueAt' then (update_activity.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_activity.attrs ? 'doneAt' then (update_activity.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_activity.attrs ? 'durationSeconds' then (update_activity.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "audience" = case when update_activity.attrs ? 'audience' then coalesce(nullif(update_activity.attrs ->> 'audience', ''), 'team') else x."audience" end,
    "restricted_roles" = case when update_activity.attrs ? 'restrictedRoles' then nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(update_activity.attrs -> 'restrictedRoles') = 'array' then update_activity.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}') else x."restricted_roles" end,
    "category" = case when update_activity.attrs ? 'category' then nullif(update_activity.attrs ->> 'category', '') else x."category" end,
    "goal_id" = case when update_activity.attrs ? 'goalId' then nullif(update_activity.attrs ->> 'goalId', '')::uuid else x."goal_id" end,
    "locked_at" = case when update_activity.attrs ? 'type' then coalesce(x."locked_at", case when update_activity.attrs ->> 'type' = any ('{note,report}'::text[]) then x."created_at" + interval '24 hours' end) else x."locked_at" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_activity.subjects is not null then
    
  if jsonb_typeof(coalesce(update_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."activity_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."update_activity"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."update_activity"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Marks an engagement done now (done true) or open again.
create or replace function "better_supabase"."complete_activity"(engagement uuid, done boolean, outcome text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := complete_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = complete_activity.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "better_supabase"."activities" x set
    "done_at" = case when complete_activity.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_activity.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if complete_activity.done then
    null;
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."complete_activity"(uuid, boolean, text) from public, anon;
grant execute on function "better_supabase"."complete_activity"(uuid, boolean, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_activity"(engagement uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = delete_activity.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  delete from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_activity"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_activity"(uuid) to authenticated, service_role;

-- A record's engagements the caller can see, newest first: done ones by
-- when they happened, open ones by when they are due. before continues
-- after the last row of the previous page.
create or replace function "better_supabase"."activities_of"(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb) into v_rows
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, coalesce(x."done_at", x."due_at", x."created_at") as at, x."id" as id
    from "better_supabase"."activities" x
    join "better_supabase"."engagement_subjects" k on k."activity_id" = x."id"
    where k."subject_type" = activities_of.subject_type and k."subject_id" = activities_of.subject_id
      and (activities_of.types is null or x."type" = any (activities_of.types))
      and (activities_of.before is null or coalesce(x."done_at", x."due_at", x."created_at") < activities_of.before)
    order by at desc, id desc
    limit least(greatest(coalesce(activities_of.page_size, 50), 1), 200)
  ) p;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."activities_of"(text, text, text[], timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."activities_of"(text, text, text[], timestamptz, integer) to authenticated, service_role;

-- The next open engagement with a due time on a record, earliest first,
-- for a "next step" and an overdue flag; null when none is planned.
create or replace function "better_supabase"."next_activity"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now())
  from "better_supabase"."activities" x
  join "better_supabase"."engagement_subjects" k on k."activity_id" = x."id"
  where k."subject_type" = next_activity.subject_type and k."subject_id" = next_activity.subject_id
    and x."done_at" is null and x."due_at" is not null
  order by x."due_at", x."id"
  limit 1
$$;
revoke execute on function "better_supabase"."next_activity"(text, text) from public, anon;
grant execute on function "better_supabase"."next_activity"(text, text) to authenticated, service_role;

-- A member's open engagements in a tenant, earliest due first: a task list.
create or replace function "better_supabase"."open_activities"(tenant uuid, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.due nulls last, p.id), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, x."due_at" as due, x."id" as id
    from "better_supabase"."activities" x
    where x."tenant_id" = open_activities.tenant
      and x."owner_user_id" = coalesce(open_activities.owner, auth.uid())
      and x."done_at" is null
      and (open_activities.due_before is null or x."due_at" < open_activities.due_before)
    order by x."due_at" nulls last, x."id"
    limit least(greatest(coalesce(open_activities.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."open_activities"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."open_activities"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- Adds an addendum to an engagement the caller can read: a new engagement of
-- the same type, title, audience and records with body, pointing at it
-- through amends_id. A locked note changes this way only.
create or replace function "better_supabase"."amend_activity"(engagement uuid, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from "better_supabase"."activities";
  v_id uuid;
  v_body text := nullif(trim(amend_activity.body), '');
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_from from "better_supabase"."activities" x
  where x."id" = amend_activity.engagement and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = x."id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = x."id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and (x."audience" <> 'restricted' or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or x."owner_user_id" = (select auth.uid()) or x."created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."activity_id" = x."id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", x."restricted_roles"))));
  if v_from."id" is null then
    raise exception 'no such engagement you can read' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'activities.write'), false)) then
    raise exception 'not allowed to amend engagements' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_body is null then
    raise exception 'an addendum needs a body' using errcode = '23502', hint = 'ACTIVITY_BODY_REQUIRED';
  end if;
  insert into "better_supabase"."activities" ("tenant_id", "type", "title", "body", "owner_user_id", "amends_id", "audience", "restricted_roles", "category", "goal_id", "locked_at", "created_by")
  values (v_from."tenant_id", v_from."type", v_from."title", v_body, auth.uid(), v_from."id", v_from."audience", v_from."restricted_roles", v_from."category", v_from."goal_id", case when v_from."type"::text = any ('{note,report}'::text[]) then now() + interval '24 hours' end, auth.uid())
  returning "id" into v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select k."tenant_id", v_id, k."subject_type", k."subject_id", k."position"
  from "better_supabase"."engagement_subjects" k where k."activity_id" = v_from."id";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."amend_activity"(uuid, text) from public, anon;
grant execute on function "better_supabase"."amend_activity"(uuid, text) to authenticated, service_role;

-- Flags an engagement as entered in error with a reason. The row stays, so
-- the record keeps what was written; the flag also locks it. The author, the
-- owner and members with activities.manage may mark it.
create or replace function "better_supabase"."mark_activity_error"(engagement uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := mark_activity_error.engagement;
  v_reason text := nullif(trim(mark_activity_error.reason), '');
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = mark_activity_error.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_reason is null then
    raise exception 'say why the engagement is in error' using errcode = '23502', hint = 'ACTIVITY_REASON_REQUIRED';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."marked_error_at" is not null) then
    raise exception 'the engagement is already marked in error' using errcode = '55000', hint = 'ACTIVITY_ALREADY_MARKED_ERROR';
  end if;
  update "better_supabase"."activities" x set
    "marked_error_at" = now(),
    "marked_error_by" = auth.uid(),
    "marked_error_reason" = v_reason,
    "locked_at" = least(coalesce(x."locked_at", now()), now())
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type"::text into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."mark_activity_error"(uuid, text) from public, anon;
grant execute on function "better_supabase"."mark_activity_error"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."activities";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."activities";
create policy bsb_tenant_scope_select on "better_supabase"."activities" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."activity_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."activities";
create policy bsb_tenant_scope_insert on "better_supabase"."activities" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."activities";
create policy bsb_tenant_scope_update on "better_supabase"."activities" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."activities";
create policy bsb_tenant_scope_delete on "better_supabase"."activities" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."engagement_subjects";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_select on "better_supabase"."engagement_subjects" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_insert on "better_supabase"."engagement_subjects" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_update on "better_supabase"."engagement_subjects" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_delete on "better_supabase"."engagement_subjects" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.activities.api: entry points for the Data API.
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

create or replace function "api"."log_activity"(tenant uuid, attrs jsonb, subjects jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."log_activity"($1, $2, $3) $$;
revoke execute on function "api"."log_activity"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "api"."log_activity"(uuid, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."update_activity"(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_activity"($1, $2, $3) $$;
revoke execute on function "api"."update_activity"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "api"."update_activity"(uuid, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."complete_activity"(engagement uuid, done boolean, outcome text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_activity"($1, $2, $3) $$;
revoke execute on function "api"."complete_activity"(uuid, boolean, text) from public, anon;
grant execute on function "api"."complete_activity"(uuid, boolean, text) to authenticated, service_role;

create or replace function "api"."delete_activity"(engagement uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_activity"($1) $$;
revoke execute on function "api"."delete_activity"(uuid) from public, anon;
grant execute on function "api"."delete_activity"(uuid) to authenticated, service_role;

create or replace function "api"."activities_of"(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."activities_of"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."activities_of"(text, text, text[], timestamptz, integer) from public, anon;
grant execute on function "api"."activities_of"(text, text, text[], timestamptz, integer) to authenticated, service_role;

create or replace function "api"."next_activity"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."next_activity"($1, $2) $$;
revoke execute on function "api"."next_activity"(text, text) from public, anon;
grant execute on function "api"."next_activity"(text, text) to authenticated, service_role;

create or replace function "api"."open_activities"(tenant uuid, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."open_activities"($1, $2, $3, $4) $$;
revoke execute on function "api"."open_activities"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "api"."open_activities"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."amend_activity"(engagement uuid, body text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."amend_activity"($1, $2) $$;
revoke execute on function "api"."amend_activity"(uuid, text) from public, anon;
grant execute on function "api"."amend_activity"(uuid, text) to authenticated, service_role;

create or replace function "api"."mark_activity_error"(engagement uuid, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mark_activity_error"($1, $2) $$;
revoke execute on function "api"."mark_activity_error"(uuid, text) from public, anon;
grant execute on function "api"."mark_activity_error"(uuid, text) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block-data activities
-- @bsb-hash sha256:3819d4d37eee891adf4bd6627ff0441d632f4d96e372321e5ff3a590794a2b2b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_members"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_members" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."engagement_subjects"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."engagement_subjects" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('activities', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block activities@3 managed
-- @bsb-hash sha256:3ca9fa3c71e46e1edf1a4460589e8e129acb69626f3a132488488c8cc127d756
-- Calls, emails, meetings, notes and tasks logged on one or more registered records, with an owner, a due time and an outcome, a record's timeline, its next step and a member's open tasks.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."activities";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagement_subjects";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Calls, emails, meetings, notes and tasks logged on one or more records.
-- better_supabase.activities is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."activities" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."activities" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."activities" add column if not exists "type" text;
alter table "better_supabase"."activities" add column if not exists "title" text check (length("title") between 1 and 500);
alter table "better_supabase"."activities" add column if not exists "body" text;
alter table "better_supabase"."activities" add column if not exists "outcome" text;
alter table "better_supabase"."activities" add column if not exists "owner_user_id" uuid;
alter table "better_supabase"."activities" add column if not exists "due_at" timestamptz;
alter table "better_supabase"."activities" add column if not exists "done_at" timestamptz;
alter table "better_supabase"."activities" add column if not exists "duration_seconds" integer check ("duration_seconds" >= 0);
alter table "better_supabase"."activities" add column if not exists "external_ref" text;
alter table "better_supabase"."activities" add column if not exists "created_by" uuid;
alter table "better_supabase"."activities" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."activities" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists "activities_owner_open_idx" on "better_supabase"."activities" ("tenant_id", "owner_user_id", "due_at") where "done_at" is null;
create index if not exists "activities_tenant_created_idx" on "better_supabase"."activities" ("tenant_id", "created_at" desc);
create unique index if not exists "activities_external_ref_idx" on "better_supabase"."activities" ("tenant_id", "external_ref") where "external_ref" is not null;
-- Progress notes: who reads an engagement, when it locks, its addenda and the
-- in-error flag.
alter table "better_supabase"."activities" add column if not exists "audience" text not null default 'team' check ("audience" in ('team', 'subject', 'restricted'));
alter table "better_supabase"."activities" add column if not exists "restricted_roles" text[];
alter table "better_supabase"."activities" add column if not exists "category" text check (length("category") between 1 and 63);
alter table "better_supabase"."activities" add column if not exists "locked_at" timestamptz;
alter table "better_supabase"."activities" add column if not exists "amends_id" uuid references "better_supabase"."activities" ("id") on delete cascade;
alter table "better_supabase"."activities" add column if not exists "goal_id" uuid;
alter table "better_supabase"."activities" add column if not exists "marked_error_at" timestamptz;
alter table "better_supabase"."activities" add column if not exists "marked_error_by" uuid;
alter table "better_supabase"."activities" add column if not exists "marked_error_reason" text check (length("marked_error_reason") between 1 and 2000);
create index if not exists "activities_amends_idx" on "better_supabase"."activities" ("amends_id");
alter table "better_supabase"."activities" enable row level security;
grant select on "better_supabase"."activities" to authenticated;
grant all on "better_supabase"."activities" to service_role;
-- better_supabase.engagement_subjects is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."engagement_subjects" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."engagement_subjects" add column if not exists "activity_id" uuid references "better_supabase"."activities" ("id") on delete cascade;
alter table "better_supabase"."engagement_subjects" add column if not exists "subject_type" text;
alter table "better_supabase"."engagement_subjects" add column if not exists "subject_id" text;
alter table "better_supabase"."engagement_subjects" add column if not exists "position" integer not null default 1;
create unique index if not exists "bsb_engagement_subjects_subject_key" on "better_supabase"."engagement_subjects" ("activity_id", "subject_type", "subject_id");
create index if not exists engagement_subjects_subject_idx on "better_supabase"."engagement_subjects" ("subject_type", "subject_id");
alter table "better_supabase"."engagement_subjects" enable row level security;
grant select on "better_supabase"."engagement_subjects" to authenticated;
grant all on "better_supabase"."engagement_subjects" to service_role;
-- A link is visible when its record is; an engagement when one of its
-- records is, or it has none. A guest of a record reads its subject notes.
drop policy if exists bsb_engagement_subjects_select on "better_supabase"."engagement_subjects";
create policy bsb_engagement_subjects_select on "better_supabase"."engagement_subjects"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));
drop policy if exists bsb_activities_select on "better_supabase"."activities";
create policy bsb_activities_select on "better_supabase"."activities"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."activity_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))));

-- Logs an engagement on the records in subjects ([{ type, id }], the first
-- is its main record). attrs: type, title, body, outcome, ownerId, dueAt,
-- doneAt, durationSeconds, externalRef and fields (the extra columns by
-- name). A known externalRef updates instead.
create or replace function "better_supabase"."log_activity"(tenant uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant uuid := log_activity.tenant;
  v_type text := log_activity.attrs ->> 'type';
  v_title text := nullif(trim(log_activity.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_activity.attrs ->> 'ownerId', '')::uuid, auth.uid());
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'activities.write'), false)) then
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ACTIVITY_TITLE_REQUIRED';
  end if;
  if nullif(log_activity.attrs ->> 'audience', '') is not null and not (log_activity.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if log_activity.attrs ? 'restrictedRoles' and jsonb_typeof(log_activity.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if nullif(log_activity.attrs ->> 'category', '') is not null and not (log_activity.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ACTIVITY_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."tenant_id" = v_tenant and x."external_ref" = log_activity.attrs ->> 'externalRef' and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_activity_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_activity.tenant, log_activity.attrs, log_activity.subjects;
    end if;
  end;
  insert into "better_supabase"."activities" ("tenant_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by", "audience", "restricted_roles", "category", "locked_at", "goal_id")
  values (v_tenant, better_supabase.as_column_type(v_type, (null::"better_supabase"."activities")."type"), v_title, log_activity.attrs ->> 'body', log_activity.attrs ->> 'outcome', v_owner, (log_activity.attrs ->> 'dueAt')::timestamptz, (log_activity.attrs ->> 'doneAt')::timestamptz, (log_activity.attrs ->> 'durationSeconds')::integer, log_activity.attrs ->> 'externalRef', auth.uid(), coalesce(nullif(log_activity.attrs ->> 'audience', ''), 'team'), nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(log_activity.attrs -> 'restrictedRoles') = 'array' then log_activity.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}'), nullif(log_activity.attrs ->> 'category', ''), case when v_type = any ('{note,report}'::text[]) then now() + interval '24 hours' end, nullif(log_activity.attrs ->> 'goalId', '')::uuid)
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at", "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."activity_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_activity_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'type', x."type", 'title', x."title", 'body', x."body", 'outcome', x."outcome", 'owner_user_id', x."owner_user_id", 'due_at', x."due_at", 'done_at', x."done_at", 'duration_seconds', x."duration_seconds", 'external_ref', x."external_ref", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at", 'audience', x."audience", 'restricted_roles', x."restricted_roles", 'category', x."category", 'locked_at', x."locked_at", 'amends_id', x."amends_id", 'goal_id', x."goal_id", 'marked_error_at', x."marked_error_at", 'marked_error_by', x."marked_error_by", 'marked_error_reason', x."marked_error_reason") || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."log_activity"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."log_activity"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys attrs names, and the records when subjects isn't null.
-- The author, the owner and members with engagements.manage may edit.
create or replace function "better_supabase"."update_activity"(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := update_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_title text;
  v_owner uuid;
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type", x."owner_user_id" into v_tenant, v_type, v_previous_owner
  from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if update_activity.attrs ? 'type' and not (update_activity.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
  end if;
  if nullif(update_activity.attrs ->> 'audience', '') is not null and not (update_activity.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if update_activity.attrs ? 'restrictedRoles' and jsonb_typeof(update_activity.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if nullif(update_activity.attrs ->> 'category', '') is not null and not (update_activity.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ACTIVITY_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "better_supabase"."activities" x set
    "type" = coalesce(better_supabase.as_column_type(update_activity.attrs ->> 'type', (null::"better_supabase"."activities")."type"), x."type"),
    "title" = coalesce(nullif(trim(update_activity.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_activity.attrs ? 'body' then update_activity.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_activity.attrs ? 'outcome' then update_activity.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_activity.attrs ? 'externalRef' then update_activity.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_activity.attrs ? 'ownerId' then nullif(update_activity.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_activity.attrs ? 'dueAt' then (update_activity.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_activity.attrs ? 'doneAt' then (update_activity.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_activity.attrs ? 'durationSeconds' then (update_activity.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "audience" = case when update_activity.attrs ? 'audience' then coalesce(nullif(update_activity.attrs ->> 'audience', ''), 'team') else x."audience" end,
    "restricted_roles" = case when update_activity.attrs ? 'restrictedRoles' then nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(update_activity.attrs -> 'restrictedRoles') = 'array' then update_activity.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}') else x."restricted_roles" end,
    "category" = case when update_activity.attrs ? 'category' then nullif(update_activity.attrs ->> 'category', '') else x."category" end,
    "goal_id" = case when update_activity.attrs ? 'goalId' then nullif(update_activity.attrs ->> 'goalId', '')::uuid else x."goal_id" end,
    "locked_at" = case when update_activity.attrs ? 'type' then coalesce(x."locked_at", case when update_activity.attrs ->> 'type' = any ('{note,report}'::text[]) then x."created_at" + interval '24 hours' end) else x."locked_at" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_activity.subjects is not null then
    
  if jsonb_typeof(coalesce(update_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."activity_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  null;
  return (select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'type', x."type", 'title', x."title", 'body', x."body", 'outcome', x."outcome", 'owner_user_id', x."owner_user_id", 'due_at', x."due_at", 'done_at', x."done_at", 'duration_seconds', x."duration_seconds", 'external_ref', x."external_ref", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at", 'audience', x."audience", 'restricted_roles', x."restricted_roles", 'category', x."category", 'locked_at', x."locked_at", 'amends_id', x."amends_id", 'goal_id', x."goal_id", 'marked_error_at', x."marked_error_at", 'marked_error_by', x."marked_error_by", 'marked_error_reason', x."marked_error_reason") || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."update_activity"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."update_activity"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Marks an engagement done now (done true) or open again.
create or replace function "better_supabase"."complete_activity"(engagement uuid, done boolean, outcome text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := complete_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = complete_activity.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "better_supabase"."activities" x set
    "done_at" = case when complete_activity.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_activity.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if complete_activity.done then
    null;
  end if;
  return (select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'type', x."type", 'title', x."title", 'body', x."body", 'outcome', x."outcome", 'owner_user_id', x."owner_user_id", 'due_at', x."due_at", 'done_at', x."done_at", 'duration_seconds', x."duration_seconds", 'external_ref', x."external_ref", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at", 'audience', x."audience", 'restricted_roles', x."restricted_roles", 'category', x."category", 'locked_at', x."locked_at", 'amends_id', x."amends_id", 'goal_id', x."goal_id", 'marked_error_at', x."marked_error_at", 'marked_error_by', x."marked_error_by", 'marked_error_reason', x."marked_error_reason") || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."complete_activity"(uuid, boolean, text) from public, anon;
grant execute on function "better_supabase"."complete_activity"(uuid, boolean, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_activity"(engagement uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = delete_activity.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  delete from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_activity"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_activity"(uuid) to authenticated, service_role;

-- A record's engagements the caller can see, newest first: done ones by
-- when they happened, open ones by when they are due. before continues
-- after the last row of the previous page.
create or replace function "better_supabase"."activities_of"(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'type', x."type", 'title', x."title", 'body', x."body", 'outcome', x."outcome", 'owner_user_id', x."owner_user_id", 'due_at', x."due_at", 'done_at', x."done_at", 'duration_seconds', x."duration_seconds", 'external_ref', x."external_ref", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at", 'audience', x."audience", 'restricted_roles', x."restricted_roles", 'category', x."category", 'locked_at', x."locked_at", 'amends_id', x."amends_id", 'goal_id', x."goal_id", 'marked_error_at', x."marked_error_at", 'marked_error_by', x."marked_error_by", 'marked_error_reason', x."marked_error_reason") || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, coalesce(x."done_at", x."due_at", x."created_at") as at, x."id" as id
    from "better_supabase"."activities" x
    join "better_supabase"."engagement_subjects" k on k."activity_id" = x."id"
    where k."subject_type" = activities_of.subject_type and k."subject_id" = activities_of.subject_id
      and (activities_of.types is null or x."type"::text = any (activities_of.types))
      and (activities_of.before is null or coalesce(x."done_at", x."due_at", x."created_at") < activities_of.before)
    order by at desc, id desc
    limit least(greatest(coalesce(activities_of.page_size, 50), 1), 200)
  ) p;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."activities_of"(text, text, text[], timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."activities_of"(text, text, text[], timestamptz, integer) to authenticated, service_role;

-- The next open engagement with a due time on a record, earliest first,
-- for a "next step" and an overdue flag; null when none is planned.
create or replace function "better_supabase"."next_activity"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'type', x."type", 'title', x."title", 'body', x."body", 'outcome', x."outcome", 'owner_user_id', x."owner_user_id", 'due_at', x."due_at", 'done_at', x."done_at", 'duration_seconds', x."duration_seconds", 'external_ref', x."external_ref", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at", 'audience', x."audience", 'restricted_roles', x."restricted_roles", 'category', x."category", 'locked_at', x."locked_at", 'amends_id', x."amends_id", 'goal_id', x."goal_id", 'marked_error_at', x."marked_error_at", 'marked_error_by', x."marked_error_by", 'marked_error_reason', x."marked_error_reason") || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now())
  from "better_supabase"."activities" x
  join "better_supabase"."engagement_subjects" k on k."activity_id" = x."id"
  where k."subject_type" = next_activity.subject_type and k."subject_id" = next_activity.subject_id
    and x."done_at" is null and x."due_at" is not null
  order by x."due_at", x."id"
  limit 1
$$;
revoke execute on function "better_supabase"."next_activity"(text, text) from public, anon;
grant execute on function "better_supabase"."next_activity"(text, text) to authenticated, service_role;

-- A member's open engagements in a tenant, earliest due first: a task list.
create or replace function "better_supabase"."open_activities"(tenant uuid, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.due nulls last, p.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'type', x."type", 'title', x."title", 'body', x."body", 'outcome', x."outcome", 'owner_user_id', x."owner_user_id", 'due_at', x."due_at", 'done_at', x."done_at", 'duration_seconds', x."duration_seconds", 'external_ref', x."external_ref", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at", 'audience', x."audience", 'restricted_roles', x."restricted_roles", 'category', x."category", 'locked_at', x."locked_at", 'amends_id', x."amends_id", 'goal_id', x."goal_id", 'marked_error_at', x."marked_error_at", 'marked_error_by', x."marked_error_by", 'marked_error_reason', x."marked_error_reason") || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, x."due_at" as due, x."id" as id
    from "better_supabase"."activities" x
    where x."tenant_id" = open_activities.tenant
      and x."owner_user_id" = coalesce(open_activities.owner, auth.uid())
      and x."done_at" is null
      and (open_activities.due_before is null or x."due_at" < open_activities.due_before)
    order by x."due_at" nulls last, x."id"
    limit least(greatest(coalesce(open_activities.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."open_activities"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."open_activities"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- Adds an addendum to an engagement the caller can read: a new engagement of
-- the same type, title, audience and records with body, pointing at it
-- through amends_id. A locked note changes this way only.
create or replace function "better_supabase"."amend_activity"(engagement uuid, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from "better_supabase"."activities";
  v_id uuid;
  v_body text := nullif(trim(amend_activity.body), '');
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_from from "better_supabase"."activities" x
  where x."id" = amend_activity.engagement and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = x."id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = x."id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and (x."audience" <> 'restricted' or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or x."owner_user_id" = (select auth.uid()) or x."created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."activity_id" = x."id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", x."restricted_roles"))));
  if v_from."id" is null then
    raise exception 'no such engagement you can read' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'activities.write'), false)) then
    raise exception 'not allowed to amend engagements' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_body is null then
    raise exception 'an addendum needs a body' using errcode = '23502', hint = 'ACTIVITY_BODY_REQUIRED';
  end if;
  insert into "better_supabase"."activities" ("tenant_id", "type", "title", "body", "owner_user_id", "amends_id", "audience", "restricted_roles", "category", "goal_id", "locked_at", "created_by")
  values (v_from."tenant_id", v_from."type", v_from."title", v_body, auth.uid(), v_from."id", v_from."audience", v_from."restricted_roles", v_from."category", v_from."goal_id", case when v_from."type"::text = any ('{note,report}'::text[]) then now() + interval '24 hours' end, auth.uid())
  returning "id" into v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select k."tenant_id", v_id, k."subject_type", k."subject_id", k."position"
  from "better_supabase"."engagement_subjects" k where k."activity_id" = v_from."id";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  return (select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'type', x."type", 'title', x."title", 'body', x."body", 'outcome', x."outcome", 'owner_user_id', x."owner_user_id", 'due_at', x."due_at", 'done_at', x."done_at", 'duration_seconds', x."duration_seconds", 'external_ref', x."external_ref", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at", 'audience', x."audience", 'restricted_roles', x."restricted_roles", 'category', x."category", 'locked_at', x."locked_at", 'amends_id', x."amends_id", 'goal_id', x."goal_id", 'marked_error_at', x."marked_error_at", 'marked_error_by', x."marked_error_by", 'marked_error_reason', x."marked_error_reason") || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."amend_activity"(uuid, text) from public, anon;
grant execute on function "better_supabase"."amend_activity"(uuid, text) to authenticated, service_role;

-- Flags an engagement as entered in error with a reason. The row stays, so
-- the record keeps what was written; the flag also locks it. The author, the
-- owner and members with activities.manage may mark it.
create or replace function "better_supabase"."mark_activity_error"(engagement uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := mark_activity_error.engagement;
  v_reason text := nullif(trim(mark_activity_error.reason), '');
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = mark_activity_error.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_reason is null then
    raise exception 'say why the engagement is in error' using errcode = '23502', hint = 'ACTIVITY_REASON_REQUIRED';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."marked_error_at" is not null) then
    raise exception 'the engagement is already marked in error' using errcode = '55000', hint = 'ACTIVITY_ALREADY_MARKED_ERROR';
  end if;
  update "better_supabase"."activities" x set
    "marked_error_at" = now(),
    "marked_error_by" = auth.uid(),
    "marked_error_reason" = v_reason,
    "locked_at" = least(coalesce(x."locked_at", now()), now())
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type"::text into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  null;
  return (select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'type', x."type", 'title', x."title", 'body', x."body", 'outcome', x."outcome", 'owner_user_id', x."owner_user_id", 'due_at', x."due_at", 'done_at', x."done_at", 'duration_seconds', x."duration_seconds", 'external_ref', x."external_ref", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at", 'audience', x."audience", 'restricted_roles', x."restricted_roles", 'category', x."category", 'locked_at', x."locked_at", 'amends_id', x."amends_id", 'goal_id', x."goal_id", 'marked_error_at', x."marked_error_at", 'marked_error_by', x."marked_error_by", 'marked_error_reason', x."marked_error_reason") || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."mark_activity_error"(uuid, text) from public, anon;
grant execute on function "better_supabase"."mark_activity_error"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."activities";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."activities";
create policy bsb_tenant_scope_select on "better_supabase"."activities" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."activity_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."activities";
create policy bsb_tenant_scope_insert on "better_supabase"."activities" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."activities";
create policy bsb_tenant_scope_update on "better_supabase"."activities" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."activities";
create policy bsb_tenant_scope_delete on "better_supabase"."activities" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."engagement_subjects";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_select on "better_supabase"."engagement_subjects" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_insert on "better_supabase"."engagement_subjects" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_update on "better_supabase"."engagement_subjects" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_delete on "better_supabase"."engagement_subjects" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block-data activities
-- @bsb-hash sha256:3819d4d37eee891adf4bd6627ff0441d632f4d96e372321e5ff3a590794a2b2b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_members"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_members" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."engagement_subjects"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."engagement_subjects" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('activities', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block activities@3 managed
-- @bsb-hash sha256:1d7453f09357e412222c8e04fb793ef45df7117e353dd74e1a208432aea9104d
-- Calls, emails, meetings, notes and tasks logged on one or more registered records, with an owner, a due time and an outcome, a record's timeline, its next step and a member's open tasks.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."activities";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."activities";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagement_subjects";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagement_subjects";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Calls, emails, meetings, notes and tasks logged on one or more records.
create table if not exists "better_supabase"."activities" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "type" text not null,
  "title" text not null check (length("title") between 1 and 500),
  "body" text,
  "outcome" text,
  "owner_user_id" uuid,
  "due_at" timestamptz,
  "done_at" timestamptz,
  "duration_seconds" integer check ("duration_seconds" >= 0),
  "external_ref" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "activities_owner_open_idx" on "better_supabase"."activities" ("org_id", "owner_user_id", "due_at") where "done_at" is null;
create index if not exists "activities_tenant_created_idx" on "better_supabase"."activities" ("org_id", "created_at" desc);
create unique index if not exists "activities_external_ref_idx" on "better_supabase"."activities" ("org_id", "external_ref") where "external_ref" is not null;
-- Progress notes: who reads an engagement, when it locks, its addenda and the
-- in-error flag.
alter table "better_supabase"."activities" add column if not exists "audience" text not null default 'team' check ("audience" in ('team', 'subject', 'restricted'));
alter table "better_supabase"."activities" add column if not exists "restricted_roles" text[];
alter table "better_supabase"."activities" add column if not exists "category" text check (length("category") between 1 and 63);
alter table "better_supabase"."activities" add column if not exists "locked_at" timestamptz;
alter table "better_supabase"."activities" add column if not exists "amends_id" uuid references "better_supabase"."activities" ("id") on delete cascade;
alter table "better_supabase"."activities" add column if not exists "goal_id" uuid;
alter table "better_supabase"."activities" add column if not exists "marked_error_at" timestamptz;
alter table "better_supabase"."activities" add column if not exists "marked_error_by" uuid;
alter table "better_supabase"."activities" add column if not exists "marked_error_reason" text check (length("marked_error_reason") between 1 and 2000);
create index if not exists "activities_amends_idx" on "better_supabase"."activities" ("amends_id");
alter table "better_supabase"."activities" enable row level security;
revoke all on "better_supabase"."activities" from public, anon, authenticated;
grant select on "better_supabase"."activities" to authenticated;
grant all on "better_supabase"."activities" to service_role;
create table if not exists "better_supabase"."engagement_subjects" (
  "org_id" uuid not null,
  "activity_id" uuid not null references "better_supabase"."activities" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "position" integer not null default 1,
  primary key ("activity_id", "subject_type", "subject_id")
);
create index if not exists engagement_subjects_subject_idx on "better_supabase"."engagement_subjects" ("subject_type", "subject_id");
alter table "better_supabase"."engagement_subjects" enable row level security;
revoke all on "better_supabase"."engagement_subjects" from public, anon, authenticated;
grant select on "better_supabase"."engagement_subjects" to authenticated;
grant all on "better_supabase"."engagement_subjects" to service_role;
-- A link is visible when its record is; an engagement when one of its
-- records is, or it has none. A guest of a record reads its subject notes.
drop policy if exists engagement_subjects_read on "better_supabase"."engagement_subjects";
create policy engagement_subjects_read on "better_supabase"."engagement_subjects"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('activities.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));
drop policy if exists activities_read on "better_supabase"."activities";
create policy activities_read on "better_supabase"."activities"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "org_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."activity_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))));

-- Logs an engagement on the records in subjects ([{ type, id }], the first
-- is its main record). attrs: type, title, body, outcome, ownerId, dueAt,
-- doneAt, durationSeconds, externalRef and fields (the extra columns by
-- name). A known externalRef updates instead.
create or replace function "better_supabase"."log_activity"(tenant uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant uuid := log_activity.tenant;
  v_type text := log_activity.attrs ->> 'type';
  v_title text := nullif(trim(log_activity.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_activity.attrs ->> 'ownerId', '')::uuid, auth.uid());
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'activities.write'), false)) then
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ACTIVITY_TITLE_REQUIRED';
  end if;
  if nullif(log_activity.attrs ->> 'audience', '') is not null and not (log_activity.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if log_activity.attrs ? 'restrictedRoles' and jsonb_typeof(log_activity.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if nullif(log_activity.attrs ->> 'category', '') is not null and not (log_activity.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ACTIVITY_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."org_id" = v_tenant and x."external_ref" = log_activity.attrs ->> 'externalRef' and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_activity_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_activity.tenant, log_activity.attrs, log_activity.subjects;
    end if;
  end;
  insert into "better_supabase"."activities" ("org_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by", "audience", "restricted_roles", "category", "locked_at", "goal_id")
  values (v_tenant, v_type, v_title, log_activity.attrs ->> 'body', log_activity.attrs ->> 'outcome', v_owner, (log_activity.attrs ->> 'dueAt')::timestamptz, (log_activity.attrs ->> 'doneAt')::timestamptz, (log_activity.attrs ->> 'durationSeconds')::integer, log_activity.attrs ->> 'externalRef', auth.uid(), coalesce(nullif(log_activity.attrs ->> 'audience', ''), 'team'), nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(log_activity.attrs -> 'restrictedRoles') = 'array' then log_activity.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}'), nullif(log_activity.attrs ->> 'category', ''), case when v_type = any ('{note,report}'::text[]) then now() + interval '24 hours' end, nullif(log_activity.attrs ->> 'goalId', '')::uuid)
  on conflict ("org_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at", "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."activity_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("org_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_activity_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."log_activity"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."log_activity"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys attrs names, and the records when subjects isn't null.
-- The author, the owner and members with engagements.manage may edit.
create or replace function "better_supabase"."update_activity"(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := update_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_title text;
  v_owner uuid;
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id", x."type", x."owner_user_id" into v_tenant, v_type, v_previous_owner
  from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'activities.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if update_activity.attrs ? 'type' and not (update_activity.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
  end if;
  if nullif(update_activity.attrs ->> 'audience', '') is not null and not (update_activity.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if update_activity.attrs ? 'restrictedRoles' and jsonb_typeof(update_activity.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if nullif(update_activity.attrs ->> 'category', '') is not null and not (update_activity.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ACTIVITY_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "better_supabase"."activities" x set
    "type" = coalesce(update_activity.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_activity.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_activity.attrs ? 'body' then update_activity.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_activity.attrs ? 'outcome' then update_activity.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_activity.attrs ? 'externalRef' then update_activity.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_activity.attrs ? 'ownerId' then nullif(update_activity.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_activity.attrs ? 'dueAt' then (update_activity.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_activity.attrs ? 'doneAt' then (update_activity.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_activity.attrs ? 'durationSeconds' then (update_activity.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "audience" = case when update_activity.attrs ? 'audience' then coalesce(nullif(update_activity.attrs ->> 'audience', ''), 'team') else x."audience" end,
    "restricted_roles" = case when update_activity.attrs ? 'restrictedRoles' then nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(update_activity.attrs -> 'restrictedRoles') = 'array' then update_activity.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}') else x."restricted_roles" end,
    "category" = case when update_activity.attrs ? 'category' then nullif(update_activity.attrs ->> 'category', '') else x."category" end,
    "goal_id" = case when update_activity.attrs ? 'goalId' then nullif(update_activity.attrs ->> 'goalId', '')::uuid else x."goal_id" end,
    "locked_at" = case when update_activity.attrs ? 'type' then coalesce(x."locked_at", case when update_activity.attrs ->> 'type' = any ('{note,report}'::text[]) then x."created_at" + interval '24 hours' end) else x."locked_at" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_activity.subjects is not null then
    
  if jsonb_typeof(coalesce(update_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."activity_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("org_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."update_activity"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."update_activity"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Marks an engagement done now (done true) or open again.
create or replace function "better_supabase"."complete_activity"(engagement uuid, done boolean, outcome text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := complete_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = complete_activity.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "better_supabase"."activities" x set
    "done_at" = case when complete_activity.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_activity.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'activities.manage'), false))
  returning x."org_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if complete_activity.done then
    null;
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."complete_activity"(uuid, boolean, text) from public, anon;
grant execute on function "better_supabase"."complete_activity"(uuid, boolean, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_activity"(engagement uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = delete_activity.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  delete from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'activities.manage'), false))
  returning x."org_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_activity"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_activity"(uuid) to authenticated, service_role;

-- A record's engagements the caller can see, newest first: done ones by
-- when they happened, open ones by when they are due. before continues
-- after the last row of the previous page.
create or replace function "better_supabase"."activities_of"(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb) into v_rows
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, coalesce(x."done_at", x."due_at", x."created_at") as at, x."id" as id
    from "better_supabase"."activities" x
    join "better_supabase"."engagement_subjects" k on k."activity_id" = x."id"
    where k."subject_type" = activities_of.subject_type and k."subject_id" = activities_of.subject_id
      and (activities_of.types is null or x."type" = any (activities_of.types))
      and (activities_of.before is null or coalesce(x."done_at", x."due_at", x."created_at") < activities_of.before)
    order by at desc, id desc
    limit least(greatest(coalesce(activities_of.page_size, 50), 1), 200)
  ) p;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."activities_of"(text, text, text[], timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."activities_of"(text, text, text[], timestamptz, integer) to authenticated, service_role;

-- The next open engagement with a due time on a record, earliest first,
-- for a "next step" and an overdue flag; null when none is planned.
create or replace function "better_supabase"."next_activity"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now())
  from "better_supabase"."activities" x
  join "better_supabase"."engagement_subjects" k on k."activity_id" = x."id"
  where k."subject_type" = next_activity.subject_type and k."subject_id" = next_activity.subject_id
    and x."done_at" is null and x."due_at" is not null
  order by x."due_at", x."id"
  limit 1
$$;
revoke execute on function "better_supabase"."next_activity"(text, text) from public, anon;
grant execute on function "better_supabase"."next_activity"(text, text) to authenticated, service_role;

-- A member's open engagements in a tenant, earliest due first: a task list.
create or replace function "better_supabase"."open_activities"(tenant uuid, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.due nulls last, p.id), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, x."due_at" as due, x."id" as id
    from "better_supabase"."activities" x
    where x."org_id" = open_activities.tenant
      and x."owner_user_id" = coalesce(open_activities.owner, auth.uid())
      and x."done_at" is null
      and (open_activities.due_before is null or x."due_at" < open_activities.due_before)
    order by x."due_at" nulls last, x."id"
    limit least(greatest(coalesce(open_activities.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."open_activities"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."open_activities"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- Adds an addendum to an engagement the caller can read: a new engagement of
-- the same type, title, audience and records with body, pointing at it
-- through amends_id. A locked note changes this way only.
create or replace function "better_supabase"."amend_activity"(engagement uuid, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from "better_supabase"."activities";
  v_id uuid;
  v_body text := nullif(trim(amend_activity.body), '');
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_from from "better_supabase"."activities" x
  where x."id" = amend_activity.engagement and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."org_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = x."id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = x."id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and (x."audience" <> 'restricted' or x."org_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or x."owner_user_id" = (select auth.uid()) or x."created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."activity_id" = x."id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", x."restricted_roles"))));
  if v_from."id" is null then
    raise exception 'no such engagement you can read' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."org_id", 'activities.write'), false)) then
    raise exception 'not allowed to amend engagements' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_body is null then
    raise exception 'an addendum needs a body' using errcode = '23502', hint = 'ACTIVITY_BODY_REQUIRED';
  end if;
  insert into "better_supabase"."activities" ("org_id", "type", "title", "body", "owner_user_id", "amends_id", "audience", "restricted_roles", "category", "goal_id", "locked_at", "created_by")
  values (v_from."org_id", v_from."type", v_from."title", v_body, auth.uid(), v_from."id", v_from."audience", v_from."restricted_roles", v_from."category", v_from."goal_id", case when v_from."type"::text = any ('{note,report}'::text[]) then now() + interval '24 hours' end, auth.uid())
  returning "id" into v_id;
  insert into "better_supabase"."engagement_subjects" ("org_id", "activity_id", "subject_type", "subject_id", "position")
  select k."org_id", v_id, k."subject_type", k."subject_id", k."position"
  from "better_supabase"."engagement_subjects" k where k."activity_id" = v_from."id";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."amend_activity"(uuid, text) from public, anon;
grant execute on function "better_supabase"."amend_activity"(uuid, text) to authenticated, service_role;

-- Flags an engagement as entered in error with a reason. The row stays, so
-- the record keeps what was written; the flag also locks it. The author, the
-- owner and members with activities.manage may mark it.
create or replace function "better_supabase"."mark_activity_error"(engagement uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := mark_activity_error.engagement;
  v_reason text := nullif(trim(mark_activity_error.reason), '');
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = mark_activity_error.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_reason is null then
    raise exception 'say why the engagement is in error' using errcode = '23502', hint = 'ACTIVITY_REASON_REQUIRED';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'activities.manage'), false)) and x."marked_error_at" is not null) then
    raise exception 'the engagement is already marked in error' using errcode = '55000', hint = 'ACTIVITY_ALREADY_MARKED_ERROR';
  end if;
  update "better_supabase"."activities" x set
    "marked_error_at" = now(),
    "marked_error_by" = auth.uid(),
    "marked_error_reason" = v_reason,
    "locked_at" = least(coalesce(x."locked_at", now()), now())
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'activities.manage'), false))
  returning x."org_id", x."type"::text into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."mark_activity_error"(uuid, text) from public, anon;
grant execute on function "better_supabase"."mark_activity_error"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."activities";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."activities";
create policy bsb_tenant_scope_select on "better_supabase"."activities" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "org_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."activity_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."activities";
create policy bsb_tenant_scope_insert on "better_supabase"."activities" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."activities";
create policy bsb_tenant_scope_update on "better_supabase"."activities" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."activities";
create policy bsb_tenant_scope_delete on "better_supabase"."activities" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."engagement_subjects";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_select on "better_supabase"."engagement_subjects" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('activities.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_insert on "better_supabase"."engagement_subjects" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_update on "better_supabase"."engagement_subjects" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_delete on "better_supabase"."engagement_subjects" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block-data activities
-- @bsb-hash sha256:3819d4d37eee891adf4bd6627ff0441d632f4d96e372321e5ff3a590794a2b2b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Subject types renamed in 0.47 (`codemod 0.47`).
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."subject_members"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."subject_members" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;
do $$ begin if exists (select 1 from pg_catalog.pg_attribute where attrelid = to_regclass('"better_supabase"."engagement_subjects"') and attname = 'subject_type' and not attisdropped) then update "better_supabase"."engagement_subjects" set "subject_type" = 'activity' where "subject_type" = 'engagement'; end if; end $$;

insert into better_supabase.blocks (name, version, mode)
values ('activities', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
