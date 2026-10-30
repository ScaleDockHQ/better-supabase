-- ==== alone: schema supabase/schemas/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block activities@1 managed
-- @bsb-hash sha256:9162a0494deca5ee5b619cd25b77661cbba44b3093f37bee76af23f098da02eb
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagements";
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
create table if not exists "better_supabase"."engagements" (
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
create index if not exists engagements_owner_open_idx on "better_supabase"."engagements" ("tenant_id", "owner_user_id", "due_at") where "done_at" is null;
create index if not exists engagements_tenant_created_idx on "better_supabase"."engagements" ("tenant_id", "created_at" desc);
create unique index if not exists engagements_external_ref_idx on "better_supabase"."engagements" ("tenant_id", "external_ref") where "external_ref" is not null;
-- Progress notes: who reads an engagement, when it locks, its addenda and the
-- in-error flag.
alter table "better_supabase"."engagements" add column if not exists "audience" text not null default 'team' check ("audience" in ('team', 'subject', 'restricted'));
alter table "better_supabase"."engagements" add column if not exists "restricted_roles" text[];
alter table "better_supabase"."engagements" add column if not exists "category" text check (length("category") between 1 and 63);
alter table "better_supabase"."engagements" add column if not exists "locked_at" timestamptz;
alter table "better_supabase"."engagements" add column if not exists "amends_id" uuid references "better_supabase"."engagements" ("id") on delete cascade;
alter table "better_supabase"."engagements" add column if not exists "goal_id" uuid;
alter table "better_supabase"."engagements" add column if not exists "marked_error_at" timestamptz;
alter table "better_supabase"."engagements" add column if not exists "marked_error_by" uuid;
alter table "better_supabase"."engagements" add column if not exists "marked_error_reason" text check (length("marked_error_reason") between 1 and 2000);
create index if not exists engagements_amends_idx on "better_supabase"."engagements" ("amends_id");
alter table "better_supabase"."engagements" enable row level security;
revoke all on "better_supabase"."engagements" from public, anon, authenticated;
grant select on "better_supabase"."engagements" to authenticated;
grant all on "better_supabase"."engagements" to service_role;
create table if not exists "better_supabase"."engagement_subjects" (
  "tenant_id" uuid not null,
  "engagement_id" uuid not null references "better_supabase"."engagements" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "position" integer not null default 1,
  primary key ("engagement_id", "subject_type", "subject_id")
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
drop policy if exists engagements_read on "better_supabase"."engagements";
create policy engagements_read on "better_supabase"."engagements"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."engagement_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))));

-- Logs an engagement on the records in subjects ([{ type, id }], the first
-- is its main record). attrs: type, title, body, outcome, ownerId, dueAt,
-- doneAt, durationSeconds, externalRef and fields (the extra columns by
-- name). A known externalRef updates instead.
create or replace function "better_supabase"."log_engagement"(tenant uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant uuid := log_engagement.tenant;
  v_type text := log_engagement.attrs ->> 'type';
  v_title text := nullif(trim(log_engagement.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_engagement.attrs ->> 'ownerId', '')::uuid, auth.uid());
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
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ENGAGEMENT_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ENGAGEMENT_TITLE_REQUIRED';
  end if;
  if nullif(log_engagement.attrs ->> 'audience', '') is not null and not (log_engagement.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if log_engagement.attrs ? 'restrictedRoles' and jsonb_typeof(log_engagement.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if nullif(log_engagement.attrs ->> 'category', '') is not null and not (log_engagement.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ENGAGEMENT_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."tenant_id" = v_tenant and x."external_ref" = log_engagement.attrs ->> 'externalRef' and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_engagement_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_engagement.tenant, log_engagement.attrs, log_engagement.subjects;
    end if;
  end;
  insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by", "audience", "restricted_roles", "category", "locked_at", "goal_id")
  values (v_tenant, v_type, v_title, log_engagement.attrs ->> 'body', log_engagement.attrs ->> 'outcome', v_owner, (log_engagement.attrs ->> 'dueAt')::timestamptz, (log_engagement.attrs ->> 'doneAt')::timestamptz, (log_engagement.attrs ->> 'durationSeconds')::integer, log_engagement.attrs ->> 'externalRef', auth.uid(), coalesce(nullif(log_engagement.attrs ->> 'audience', ''), 'team'), nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(log_engagement.attrs -> 'restrictedRoles') = 'array' then log_engagement.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}'), nullif(log_engagement.attrs ->> 'category', ''), case when v_type = any ('{note,report}'::text[]) then now() + interval '24 hours' end, nullif(log_engagement.attrs ->> 'goalId', '')::uuid)
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at", "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_engagement_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."log_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."log_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys attrs names, and the records when subjects isn't null.
-- The author, the owner and members with engagements.manage may edit.
create or replace function "better_supabase"."update_engagement"(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := update_engagement.engagement;
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
  from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if update_engagement.attrs ? 'type' and not (update_engagement.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  if nullif(update_engagement.attrs ->> 'audience', '') is not null and not (update_engagement.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if update_engagement.attrs ? 'restrictedRoles' and jsonb_typeof(update_engagement.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if nullif(update_engagement.attrs ->> 'category', '') is not null and not (update_engagement.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ENGAGEMENT_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  update "better_supabase"."engagements" x set
    "type" = coalesce(update_engagement.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_engagement.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_engagement.attrs ? 'body' then update_engagement.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_engagement.attrs ? 'outcome' then update_engagement.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_engagement.attrs ? 'externalRef' then update_engagement.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_engagement.attrs ? 'ownerId' then nullif(update_engagement.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_engagement.attrs ? 'dueAt' then (update_engagement.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_engagement.attrs ? 'doneAt' then (update_engagement.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_engagement.attrs ? 'durationSeconds' then (update_engagement.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "audience" = case when update_engagement.attrs ? 'audience' then coalesce(nullif(update_engagement.attrs ->> 'audience', ''), 'team') else x."audience" end,
    "restricted_roles" = case when update_engagement.attrs ? 'restrictedRoles' then nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(update_engagement.attrs -> 'restrictedRoles') = 'array' then update_engagement.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}') else x."restricted_roles" end,
    "category" = case when update_engagement.attrs ? 'category' then nullif(update_engagement.attrs ->> 'category', '') else x."category" end,
    "goal_id" = case when update_engagement.attrs ? 'goalId' then nullif(update_engagement.attrs ->> 'goalId', '')::uuid else x."goal_id" end,
    "locked_at" = case when update_engagement.attrs ? 'type' then coalesce(x."locked_at", case when update_engagement.attrs ->> 'type' = any ('{note,report}'::text[]) then x."created_at" + interval '24 hours' end) else x."locked_at" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_engagement.subjects is not null then
    
  if jsonb_typeof(coalesce(update_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."update_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."update_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Marks an engagement done now (done true) or open again.
create or replace function "better_supabase"."complete_engagement"(engagement uuid, done boolean, outcome text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := complete_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = complete_engagement.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  update "better_supabase"."engagements" x set
    "done_at" = case when complete_engagement.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_engagement.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if complete_engagement.done then
    null;
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."complete_engagement"(uuid, boolean, text) from public, anon;
grant execute on function "better_supabase"."complete_engagement"(uuid, boolean, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_engagement"(engagement uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = delete_engagement.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  delete from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_engagement"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_engagement"(uuid) to authenticated, service_role;

-- A record's engagements the caller can see, newest first: done ones by
-- when they happened, open ones by when they are due. before continues
-- after the last row of the previous page.
create or replace function "better_supabase"."engagements_of"(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, coalesce(x."done_at", x."due_at", x."created_at") as at, x."id" as id
    from "better_supabase"."engagements" x
    join "better_supabase"."engagement_subjects" k on k."engagement_id" = x."id"
    where k."subject_type" = engagements_of.subject_type and k."subject_id" = engagements_of.subject_id
      and (engagements_of.types is null or x."type" = any (engagements_of.types))
      and (engagements_of.before is null or coalesce(x."done_at", x."due_at", x."created_at") < engagements_of.before)
    order by at desc, id desc
    limit least(greatest(coalesce(engagements_of.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."engagements_of"(text, text, text[], timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."engagements_of"(text, text, text[], timestamptz, integer) to authenticated, service_role;

-- The next open engagement with a due time on a record, earliest first,
-- for a "next step" and an overdue flag; null when none is planned.
create or replace function "better_supabase"."next_engagement"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now())
  from "better_supabase"."engagements" x
  join "better_supabase"."engagement_subjects" k on k."engagement_id" = x."id"
  where k."subject_type" = next_engagement.subject_type and k."subject_id" = next_engagement.subject_id
    and x."done_at" is null and x."due_at" is not null
  order by x."due_at", x."id"
  limit 1
$$;
revoke execute on function "better_supabase"."next_engagement"(text, text) from public, anon;
grant execute on function "better_supabase"."next_engagement"(text, text) to authenticated, service_role;

-- A member's open engagements in a tenant, earliest due first: a task list.
create or replace function "better_supabase"."open_engagements"(tenant uuid, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.due nulls last, p.id), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, x."due_at" as due, x."id" as id
    from "better_supabase"."engagements" x
    where x."tenant_id" = open_engagements.tenant
      and x."owner_user_id" = coalesce(open_engagements.owner, auth.uid())
      and x."done_at" is null
      and (open_engagements.due_before is null or x."due_at" < open_engagements.due_before)
    order by x."due_at" nulls last, x."id"
    limit least(greatest(coalesce(open_engagements.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."open_engagements"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."open_engagements"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- Adds an addendum to an engagement the caller can read: a new engagement of
-- the same type, title, audience and records with body, pointing at it
-- through amends_id. A locked note changes this way only.
create or replace function "better_supabase"."amend_engagement"(engagement uuid, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from "better_supabase"."engagements";
  v_id uuid;
  v_body text := nullif(trim(amend_engagement.body), '');
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_from from "better_supabase"."engagements" x
  where x."id" = amend_engagement.engagement and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = x."id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = x."id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and (x."audience" <> 'restricted' or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or x."owner_user_id" = (select auth.uid()) or x."created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."engagement_id" = x."id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", x."restricted_roles"))));
  if v_from."id" is null then
    raise exception 'no such engagement you can read' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'activities.write'), false)) then
    raise exception 'not allowed to amend engagements' using errcode = '42501', hint = 'ENGAGEMENT_FORBIDDEN';
  end if;
  if v_body is null then
    raise exception 'an addendum needs a body' using errcode = '23502', hint = 'ENGAGEMENT_BODY_REQUIRED';
  end if;
  insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "owner_user_id", "amends_id", "audience", "restricted_roles", "category", "goal_id", "locked_at", "created_by")
  values (v_from."tenant_id", v_from."type", v_from."title", v_body, auth.uid(), v_from."id", v_from."audience", v_from."restricted_roles", v_from."category", v_from."goal_id", case when v_from."type"::text = any ('{note,report}'::text[]) then now() + interval '24 hours' end, auth.uid())
  returning "id" into v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select k."tenant_id", v_id, k."subject_type", k."subject_id", k."position"
  from "better_supabase"."engagement_subjects" k where k."engagement_id" = v_from."id";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."amend_engagement"(uuid, text) from public, anon;
grant execute on function "better_supabase"."amend_engagement"(uuid, text) to authenticated, service_role;

-- Flags an engagement as entered in error with a reason. The row stays, so
-- the record keeps what was written; the flag also locks it. The author, the
-- owner and members with activities.manage may mark it.
create or replace function "better_supabase"."mark_engagement_error"(engagement uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := mark_engagement_error.engagement;
  v_reason text := nullif(trim(mark_engagement_error.reason), '');
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = mark_engagement_error.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_reason is null then
    raise exception 'say why the engagement is in error' using errcode = '23502', hint = 'ENGAGEMENT_REASON_REQUIRED';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."marked_error_at" is not null) then
    raise exception 'the engagement is already marked in error' using errcode = '55000', hint = 'ENGAGEMENT_ALREADY_MARKED_ERROR';
  end if;
  update "better_supabase"."engagements" x set
    "marked_error_at" = now(),
    "marked_error_by" = auth.uid(),
    "marked_error_reason" = v_reason,
    "locked_at" = least(coalesce(x."locked_at", now()), now())
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type"::text into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."mark_engagement_error"(uuid, text) from public, anon;
grant execute on function "better_supabase"."mark_engagement_error"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."engagements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagements";
create policy bsb_tenant_scope_select on "better_supabase"."engagements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."engagement_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagements";
create policy bsb_tenant_scope_insert on "better_supabase"."engagements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagements";
create policy bsb_tenant_scope_update on "better_supabase"."engagements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagements";
create policy bsb_tenant_scope_delete on "better_supabase"."engagements" as restrictive
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
-- @bsb-hash sha256:fc154848e88c3534185b137ea33c45a51323b129c973dbf0c81ce9080a1f7c52
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('activities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block activities@1 managed
-- @bsb-hash sha256:1a3cc175a3ba7891012a7f29c8611b071a2b89613f4dd7ea020eec6f2ca7b18a
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagements";
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
create table if not exists "better_supabase"."engagements" (
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
create index if not exists engagements_owner_open_idx on "better_supabase"."engagements" ("tenant_id", "owner_user_id", "due_at") where "done_at" is null;
create index if not exists engagements_tenant_created_idx on "better_supabase"."engagements" ("tenant_id", "created_at" desc);
create unique index if not exists engagements_external_ref_idx on "better_supabase"."engagements" ("tenant_id", "external_ref") where "external_ref" is not null;
-- Progress notes: who reads an engagement, when it locks, its addenda and the
-- in-error flag.
alter table "better_supabase"."engagements" add column if not exists "audience" text not null default 'team' check ("audience" in ('team', 'subject', 'restricted'));
alter table "better_supabase"."engagements" add column if not exists "restricted_roles" text[];
alter table "better_supabase"."engagements" add column if not exists "category" text check (length("category") between 1 and 63);
alter table "better_supabase"."engagements" add column if not exists "locked_at" timestamptz;
alter table "better_supabase"."engagements" add column if not exists "amends_id" uuid references "better_supabase"."engagements" ("id") on delete cascade;
alter table "better_supabase"."engagements" add column if not exists "goal_id" uuid;
alter table "better_supabase"."engagements" add column if not exists "marked_error_at" timestamptz;
alter table "better_supabase"."engagements" add column if not exists "marked_error_by" uuid;
alter table "better_supabase"."engagements" add column if not exists "marked_error_reason" text check (length("marked_error_reason") between 1 and 2000);
create index if not exists engagements_amends_idx on "better_supabase"."engagements" ("amends_id");
alter table "better_supabase"."engagements" enable row level security;
revoke all on "better_supabase"."engagements" from public, anon, authenticated;
grant select on "better_supabase"."engagements" to authenticated;
grant all on "better_supabase"."engagements" to service_role;
create table if not exists "better_supabase"."engagement_subjects" (
  "tenant_id" uuid not null,
  "engagement_id" uuid not null references "better_supabase"."engagements" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "position" integer not null default 1,
  primary key ("engagement_id", "subject_type", "subject_id")
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
    select 1 from "better_supabase"."engagements" x
    join "better_supabase"."engagement_subjects" k on k."engagement_id" = x."id"
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
  using (("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read')) or ((("tenant_id")::text, ("subject_type")::text, ("subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) and "better_supabase"."engagement_guest_readable"("engagement_id")));
drop policy if exists engagements_read on "better_supabase"."engagements";
create policy engagements_read on "better_supabase"."engagements"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."engagement_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles")))) or ("audience" = 'subject' and "better_supabase"."engagement_guest_readable"("id")));

-- Logs an engagement on the records in subjects ([{ type, id }], the first
-- is its main record). attrs: type, title, body, outcome, ownerId, dueAt,
-- doneAt, durationSeconds, externalRef and fields (the extra columns by
-- name). A known externalRef updates instead.
create or replace function "better_supabase"."log_engagement"(tenant uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant uuid := log_engagement.tenant;
  v_type text := log_engagement.attrs ->> 'type';
  v_title text := nullif(trim(log_engagement.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_engagement.attrs ->> 'ownerId', '')::uuid, auth.uid());
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
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ENGAGEMENT_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ENGAGEMENT_TITLE_REQUIRED';
  end if;
  if nullif(log_engagement.attrs ->> 'audience', '') is not null and not (log_engagement.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if log_engagement.attrs ? 'restrictedRoles' and jsonb_typeof(log_engagement.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if nullif(log_engagement.attrs ->> 'category', '') is not null and not (log_engagement.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ENGAGEMENT_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."tenant_id" = v_tenant and x."external_ref" = log_engagement.attrs ->> 'externalRef' and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_engagement_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_engagement.tenant, log_engagement.attrs, log_engagement.subjects;
    end if;
  end;
  insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by", "audience", "restricted_roles", "category", "locked_at", "goal_id")
  values (v_tenant, v_type, v_title, log_engagement.attrs ->> 'body', log_engagement.attrs ->> 'outcome', v_owner, (log_engagement.attrs ->> 'dueAt')::timestamptz, (log_engagement.attrs ->> 'doneAt')::timestamptz, (log_engagement.attrs ->> 'durationSeconds')::integer, log_engagement.attrs ->> 'externalRef', auth.uid(), coalesce(nullif(log_engagement.attrs ->> 'audience', ''), 'team'), nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(log_engagement.attrs -> 'restrictedRoles') = 'array' then log_engagement.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}'), nullif(log_engagement.attrs ->> 'category', ''), case when v_type = any ('{note,report}'::text[]) then now() + interval '24 hours' end, nullif(log_engagement.attrs ->> 'goalId', '')::uuid)
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at", "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('engagement.logged', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
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
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_engagement_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."log_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."log_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys attrs names, and the records when subjects isn't null.
-- The author, the owner and members with engagements.manage may edit.
create or replace function "better_supabase"."update_engagement"(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := update_engagement.engagement;
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
  from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if update_engagement.attrs ? 'type' and not (update_engagement.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  if nullif(update_engagement.attrs ->> 'audience', '') is not null and not (update_engagement.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if update_engagement.attrs ? 'restrictedRoles' and jsonb_typeof(update_engagement.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if nullif(update_engagement.attrs ->> 'category', '') is not null and not (update_engagement.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ENGAGEMENT_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  update "better_supabase"."engagements" x set
    "type" = coalesce(update_engagement.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_engagement.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_engagement.attrs ? 'body' then update_engagement.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_engagement.attrs ? 'outcome' then update_engagement.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_engagement.attrs ? 'externalRef' then update_engagement.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_engagement.attrs ? 'ownerId' then nullif(update_engagement.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_engagement.attrs ? 'dueAt' then (update_engagement.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_engagement.attrs ? 'doneAt' then (update_engagement.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_engagement.attrs ? 'durationSeconds' then (update_engagement.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "audience" = case when update_engagement.attrs ? 'audience' then coalesce(nullif(update_engagement.attrs ->> 'audience', ''), 'team') else x."audience" end,
    "restricted_roles" = case when update_engagement.attrs ? 'restrictedRoles' then nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(update_engagement.attrs -> 'restrictedRoles') = 'array' then update_engagement.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}') else x."restricted_roles" end,
    "category" = case when update_engagement.attrs ? 'category' then nullif(update_engagement.attrs ->> 'category', '') else x."category" end,
    "goal_id" = case when update_engagement.attrs ? 'goalId' then nullif(update_engagement.attrs ->> 'goalId', '')::uuid else x."goal_id" end,
    "locked_at" = case when update_engagement.attrs ? 'type' then coalesce(x."locked_at", case when update_engagement.attrs ->> 'type' = any ('{note,report}'::text[]) then x."created_at" + interval '24 hours' end) else x."locked_at" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_engagement.subjects is not null then
    
  if jsonb_typeof(coalesce(update_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  perform "better_supabase".emit_event('engagement.updated', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
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
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."update_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."update_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Marks an engagement done now (done true) or open again.
create or replace function "better_supabase"."complete_engagement"(engagement uuid, done boolean, outcome text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := complete_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = complete_engagement.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  update "better_supabase"."engagements" x set
    "done_at" = case when complete_engagement.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_engagement.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if complete_engagement.done then
    perform "better_supabase".emit_event('engagement.completed', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."complete_engagement"(uuid, boolean, text) from public, anon;
grant execute on function "better_supabase"."complete_engagement"(uuid, boolean, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_engagement"(engagement uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = delete_engagement.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  delete from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  perform "better_supabase".emit_event('engagement.deleted', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_engagement"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_engagement"(uuid) to authenticated, service_role;

-- A record's engagements the caller can see, newest first: done ones by
-- when they happened, open ones by when they are due. before continues
-- after the last row of the previous page.
create or replace function "better_supabase"."engagements_of"(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, coalesce(x."done_at", x."due_at", x."created_at") as at, x."id" as id
    from "better_supabase"."engagements" x
    join "better_supabase"."engagement_subjects" k on k."engagement_id" = x."id"
    where k."subject_type" = engagements_of.subject_type and k."subject_id" = engagements_of.subject_id
      and (engagements_of.types is null or x."type" = any (engagements_of.types))
      and (engagements_of.before is null or coalesce(x."done_at", x."due_at", x."created_at") < engagements_of.before)
    order by at desc, id desc
    limit least(greatest(coalesce(engagements_of.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."engagements_of"(text, text, text[], timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."engagements_of"(text, text, text[], timestamptz, integer) to authenticated, service_role;

-- The next open engagement with a due time on a record, earliest first,
-- for a "next step" and an overdue flag; null when none is planned.
create or replace function "better_supabase"."next_engagement"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now())
  from "better_supabase"."engagements" x
  join "better_supabase"."engagement_subjects" k on k."engagement_id" = x."id"
  where k."subject_type" = next_engagement.subject_type and k."subject_id" = next_engagement.subject_id
    and x."done_at" is null and x."due_at" is not null
  order by x."due_at", x."id"
  limit 1
$$;
revoke execute on function "better_supabase"."next_engagement"(text, text) from public, anon;
grant execute on function "better_supabase"."next_engagement"(text, text) to authenticated, service_role;

-- A member's open engagements in a tenant, earliest due first: a task list.
create or replace function "better_supabase"."open_engagements"(tenant uuid, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.due nulls last, p.id), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, x."due_at" as due, x."id" as id
    from "better_supabase"."engagements" x
    where x."tenant_id" = open_engagements.tenant
      and x."owner_user_id" = coalesce(open_engagements.owner, auth.uid())
      and x."done_at" is null
      and (open_engagements.due_before is null or x."due_at" < open_engagements.due_before)
    order by x."due_at" nulls last, x."id"
    limit least(greatest(coalesce(open_engagements.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."open_engagements"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."open_engagements"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- Adds an addendum to an engagement the caller can read: a new engagement of
-- the same type, title, audience and records with body, pointing at it
-- through amends_id. A locked note changes this way only.
create or replace function "better_supabase"."amend_engagement"(engagement uuid, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from "better_supabase"."engagements";
  v_id uuid;
  v_body text := nullif(trim(amend_engagement.body), '');
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_from from "better_supabase"."engagements" x
  where x."id" = amend_engagement.engagement and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = x."id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = x."id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and (x."audience" <> 'restricted' or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or x."owner_user_id" = (select auth.uid()) or x."created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."engagement_id" = x."id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", x."restricted_roles"))));
  if v_from."id" is null then
    raise exception 'no such engagement you can read' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'activities.write'), false)) then
    raise exception 'not allowed to amend engagements' using errcode = '42501', hint = 'ENGAGEMENT_FORBIDDEN';
  end if;
  if v_body is null then
    raise exception 'an addendum needs a body' using errcode = '23502', hint = 'ENGAGEMENT_BODY_REQUIRED';
  end if;
  insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "owner_user_id", "amends_id", "audience", "restricted_roles", "category", "goal_id", "locked_at", "created_by")
  values (v_from."tenant_id", v_from."type", v_from."title", v_body, auth.uid(), v_from."id", v_from."audience", v_from."restricted_roles", v_from."category", v_from."goal_id", case when v_from."type"::text = any ('{note,report}'::text[]) then now() + interval '24 hours' end, auth.uid())
  returning "id" into v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select k."tenant_id", v_id, k."subject_type", k."subject_id", k."position"
  from "better_supabase"."engagement_subjects" k where k."engagement_id" = v_from."id";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('engagement.amended', jsonb_build_object('organizationId', v_from."tenant_id", 'engagementId', v_id, 'type', v_from."type"::text, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'amendsId', v_from."id"), 'engagements/' || v_id::text, (v_from."tenant_id"::text)::text, null, 'better-supabase/activities');
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."amend_engagement"(uuid, text) from public, anon;
grant execute on function "better_supabase"."amend_engagement"(uuid, text) to authenticated, service_role;

-- Flags an engagement as entered in error with a reason. The row stays, so
-- the record keeps what was written; the flag also locks it. The author, the
-- owner and members with activities.manage may mark it.
create or replace function "better_supabase"."mark_engagement_error"(engagement uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := mark_engagement_error.engagement;
  v_reason text := nullif(trim(mark_engagement_error.reason), '');
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = mark_engagement_error.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_reason is null then
    raise exception 'say why the engagement is in error' using errcode = '23502', hint = 'ENGAGEMENT_REASON_REQUIRED';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."marked_error_at" is not null) then
    raise exception 'the engagement is already marked in error' using errcode = '55000', hint = 'ENGAGEMENT_ALREADY_MARKED_ERROR';
  end if;
  update "better_supabase"."engagements" x set
    "marked_error_at" = now(),
    "marked_error_by" = auth.uid(),
    "marked_error_reason" = v_reason,
    "locked_at" = least(coalesce(x."locked_at", now()), now())
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type"::text into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  perform "better_supabase".emit_event('engagement.error_marked', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'reason', v_reason), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."mark_engagement_error"(uuid, text) from public, anon;
grant execute on function "better_supabase"."mark_engagement_error"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."engagements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagements";
create policy bsb_tenant_scope_select on "better_supabase"."engagements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."engagement_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles")))) or ("audience" = 'subject' and "better_supabase"."engagement_guest_readable"("id")))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagements";
create policy bsb_tenant_scope_insert on "better_supabase"."engagements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagements";
create policy bsb_tenant_scope_update on "better_supabase"."engagements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagements";
create policy bsb_tenant_scope_delete on "better_supabase"."engagements" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."engagement_subjects";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagement_subjects";
create policy bsb_tenant_scope_select on "better_supabase"."engagement_subjects" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read')) or ((("tenant_id")::text, ("subject_type")::text, ("subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) and "better_supabase"."engagement_guest_readable"("engagement_id")))
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
-- @bsb-hash sha256:fc154848e88c3534185b137ea33c45a51323b129c973dbf0c81ce9080a1f7c52
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('activities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block activities@1 managed
-- @bsb-hash sha256:0446b23f951c6f960cc6d20005df18ba5e6fddf1d0ff8b422e32bdec9b6173dc
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
    drop policy if exists bsb_tenant_scope on "app_private"."engagements";
    drop policy if exists bsb_tenant_scope_select on "app_private"."engagements";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."engagements";
    drop policy if exists bsb_tenant_scope_update on "app_private"."engagements";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."engagements";
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
create table if not exists "app_private"."engagements" (
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
create index if not exists engagements_owner_open_idx on "app_private"."engagements" ("tenant_id", "owner_user_id", "due_at") where "done_at" is null;
create index if not exists engagements_tenant_created_idx on "app_private"."engagements" ("tenant_id", "created_at" desc);
create unique index if not exists engagements_external_ref_idx on "app_private"."engagements" ("tenant_id", "external_ref") where "external_ref" is not null;
-- Progress notes: who reads an engagement, when it locks, its addenda and the
-- in-error flag.
alter table "app_private"."engagements" add column if not exists "audience" text not null default 'team' check ("audience" in ('team', 'subject', 'restricted'));
alter table "app_private"."engagements" add column if not exists "restricted_roles" text[];
alter table "app_private"."engagements" add column if not exists "category" text check (length("category") between 1 and 63);
alter table "app_private"."engagements" add column if not exists "locked_at" timestamptz;
alter table "app_private"."engagements" add column if not exists "amends_id" uuid references "app_private"."engagements" ("id") on delete cascade;
alter table "app_private"."engagements" add column if not exists "goal_id" uuid;
alter table "app_private"."engagements" add column if not exists "marked_error_at" timestamptz;
alter table "app_private"."engagements" add column if not exists "marked_error_by" uuid;
alter table "app_private"."engagements" add column if not exists "marked_error_reason" text check (length("marked_error_reason") between 1 and 2000);
create index if not exists engagements_amends_idx on "app_private"."engagements" ("amends_id");
alter table "app_private"."engagements" enable row level security;
revoke all on "app_private"."engagements" from public, anon, authenticated;
grant select on "app_private"."engagements" to authenticated;
grant all on "app_private"."engagements" to service_role;
create table if not exists "app_private"."engagement_subjects" (
  "tenant_id" uuid not null,
  "engagement_id" uuid not null references "app_private"."engagements" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "position" integer not null default 1,
  primary key ("engagement_id", "subject_type", "subject_id")
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
drop policy if exists engagements_read on "app_private"."engagements";
create policy engagements_read on "app_private"."engagements"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "app_private"."engagement_subjects" lx where lx."engagement_id" = "id")
  or exists (select 1 from "app_private"."engagement_subjects" lx where lx."engagement_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "app_private"."engagement_subjects" nx where nx."engagement_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))));

-- Logs an engagement on the records in subjects ([{ type, id }], the first
-- is its main record). attrs: type, title, body, outcome, ownerId, dueAt,
-- doneAt, durationSeconds, externalRef and fields (the extra columns by
-- name). A known externalRef updates instead.
create or replace function "app_private"."log_engagement"(tenant uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant uuid := log_engagement.tenant;
  v_type text := log_engagement.attrs ->> 'type';
  v_title text := nullif(trim(log_engagement.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_engagement.attrs ->> 'ownerId', '')::uuid, auth.uid());
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
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ENGAGEMENT_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ENGAGEMENT_TITLE_REQUIRED';
  end if;
  if nullif(log_engagement.attrs ->> 'audience', '') is not null and not (log_engagement.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if log_engagement.attrs ? 'restrictedRoles' and jsonb_typeof(log_engagement.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if nullif(log_engagement.attrs ->> 'category', '') is not null and not (log_engagement.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ENGAGEMENT_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "app_private"."engagements" x where x."tenant_id" = v_tenant and x."external_ref" = log_engagement.attrs ->> 'externalRef' and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_engagement_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_engagement.tenant, log_engagement.attrs, log_engagement.subjects;
    end if;
  end;
  insert into "app_private"."engagements" ("tenant_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by", "audience", "restricted_roles", "category", "locked_at", "goal_id")
  values (v_tenant, v_type, v_title, log_engagement.attrs ->> 'body', log_engagement.attrs ->> 'outcome', v_owner, (log_engagement.attrs ->> 'dueAt')::timestamptz, (log_engagement.attrs ->> 'doneAt')::timestamptz, (log_engagement.attrs ->> 'durationSeconds')::integer, log_engagement.attrs ->> 'externalRef', auth.uid(), coalesce(nullif(log_engagement.attrs ->> 'audience', ''), 'team'), nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(log_engagement.attrs -> 'restrictedRoles') = 'array' then log_engagement.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}'), nullif(log_engagement.attrs ->> 'category', ''), case when v_type = any ('{note,report}'::text[]) then now() + interval '24 hours' end, nullif(log_engagement.attrs ->> 'goalId', '')::uuid)
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at", "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "app_private"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "app_private"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_engagement_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "app_private"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."log_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "app_private"."log_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys attrs names, and the records when subjects isn't null.
-- The author, the owner and members with engagements.manage may edit.
create or replace function "app_private"."update_engagement"(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := update_engagement.engagement;
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
  from "app_private"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if update_engagement.attrs ? 'type' and not (update_engagement.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  if nullif(update_engagement.attrs ->> 'audience', '') is not null and not (update_engagement.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if update_engagement.attrs ? 'restrictedRoles' and jsonb_typeof(update_engagement.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if nullif(update_engagement.attrs ->> 'category', '') is not null and not (update_engagement.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ENGAGEMENT_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "app_private"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  update "app_private"."engagements" x set
    "type" = coalesce(update_engagement.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_engagement.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_engagement.attrs ? 'body' then update_engagement.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_engagement.attrs ? 'outcome' then update_engagement.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_engagement.attrs ? 'externalRef' then update_engagement.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_engagement.attrs ? 'ownerId' then nullif(update_engagement.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_engagement.attrs ? 'dueAt' then (update_engagement.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_engagement.attrs ? 'doneAt' then (update_engagement.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_engagement.attrs ? 'durationSeconds' then (update_engagement.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "audience" = case when update_engagement.attrs ? 'audience' then coalesce(nullif(update_engagement.attrs ->> 'audience', ''), 'team') else x."audience" end,
    "restricted_roles" = case when update_engagement.attrs ? 'restrictedRoles' then nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(update_engagement.attrs -> 'restrictedRoles') = 'array' then update_engagement.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}') else x."restricted_roles" end,
    "category" = case when update_engagement.attrs ? 'category' then nullif(update_engagement.attrs ->> 'category', '') else x."category" end,
    "goal_id" = case when update_engagement.attrs ? 'goalId' then nullif(update_engagement.attrs ->> 'goalId', '')::uuid else x."goal_id" end,
    "locked_at" = case when update_engagement.attrs ? 'type' then coalesce(x."locked_at", case when update_engagement.attrs ->> 'type' = any ('{note,report}'::text[]) then x."created_at" + interval '24 hours' end) else x."locked_at" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_engagement.subjects is not null then
    
  if jsonb_typeof(coalesce(update_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "app_private"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "app_private"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "app_private"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."update_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "app_private"."update_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Marks an engagement done now (done true) or open again.
create or replace function "app_private"."complete_engagement"(engagement uuid, done boolean, outcome text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := complete_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."engagement_id" = complete_engagement.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "app_private"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  update "app_private"."engagements" x set
    "done_at" = case when complete_engagement.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_engagement.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if complete_engagement.done then
    null;
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "app_private"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."complete_engagement"(uuid, boolean, text) from public, anon;
grant execute on function "app_private"."complete_engagement"(uuid, boolean, text) to authenticated, service_role;

create or replace function "app_private"."delete_engagement"(engagement uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."engagement_id" = delete_engagement.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "app_private"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  delete from "app_private"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_engagement"(uuid) from public, anon;
grant execute on function "app_private"."delete_engagement"(uuid) to authenticated, service_role;

-- A record's engagements the caller can see, newest first: done ones by
-- when they happened, open ones by when they are due. before continues
-- after the last row of the previous page.
create or replace function "app_private"."engagements_of"(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, coalesce(x."done_at", x."due_at", x."created_at") as at, x."id" as id
    from "app_private"."engagements" x
    join "app_private"."engagement_subjects" k on k."engagement_id" = x."id"
    where k."subject_type" = engagements_of.subject_type and k."subject_id" = engagements_of.subject_id
      and (engagements_of.types is null or x."type" = any (engagements_of.types))
      and (engagements_of.before is null or coalesce(x."done_at", x."due_at", x."created_at") < engagements_of.before)
    order by at desc, id desc
    limit least(greatest(coalesce(engagements_of.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "app_private"."engagements_of"(text, text, text[], timestamptz, integer) from public, anon;
grant execute on function "app_private"."engagements_of"(text, text, text[], timestamptz, integer) to authenticated, service_role;

-- The next open engagement with a due time on a record, earliest first,
-- for a "next step" and an overdue flag; null when none is planned.
create or replace function "app_private"."next_engagement"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now())
  from "app_private"."engagements" x
  join "app_private"."engagement_subjects" k on k."engagement_id" = x."id"
  where k."subject_type" = next_engagement.subject_type and k."subject_id" = next_engagement.subject_id
    and x."done_at" is null and x."due_at" is not null
  order by x."due_at", x."id"
  limit 1
$$;
revoke execute on function "app_private"."next_engagement"(text, text) from public, anon;
grant execute on function "app_private"."next_engagement"(text, text) to authenticated, service_role;

-- A member's open engagements in a tenant, earliest due first: a task list.
create or replace function "app_private"."open_engagements"(tenant uuid, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.due nulls last, p.id), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, x."due_at" as due, x."id" as id
    from "app_private"."engagements" x
    where x."tenant_id" = open_engagements.tenant
      and x."owner_user_id" = coalesce(open_engagements.owner, auth.uid())
      and x."done_at" is null
      and (open_engagements.due_before is null or x."due_at" < open_engagements.due_before)
    order by x."due_at" nulls last, x."id"
    limit least(greatest(coalesce(open_engagements.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "app_private"."open_engagements"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "app_private"."open_engagements"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- Adds an addendum to an engagement the caller can read: a new engagement of
-- the same type, title, audience and records with body, pointing at it
-- through amends_id. A locked note changes this way only.
create or replace function "app_private"."amend_engagement"(engagement uuid, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from "app_private"."engagements";
  v_id uuid;
  v_body text := nullif(trim(amend_engagement.body), '');
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_from from "app_private"."engagements" x
  where x."id" = amend_engagement.engagement and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "app_private"."engagement_subjects" lx where lx."engagement_id" = x."id")
  or exists (select 1 from "app_private"."engagement_subjects" lx where lx."engagement_id" = x."id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and (x."audience" <> 'restricted' or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or x."owner_user_id" = (select auth.uid()) or x."created_by" = (select auth.uid()) or exists (select 1 from "app_private"."engagement_subjects" nx where nx."engagement_id" = x."id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", x."restricted_roles"))));
  if v_from."id" is null then
    raise exception 'no such engagement you can read' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'activities.write'), false)) then
    raise exception 'not allowed to amend engagements' using errcode = '42501', hint = 'ENGAGEMENT_FORBIDDEN';
  end if;
  if v_body is null then
    raise exception 'an addendum needs a body' using errcode = '23502', hint = 'ENGAGEMENT_BODY_REQUIRED';
  end if;
  insert into "app_private"."engagements" ("tenant_id", "type", "title", "body", "owner_user_id", "amends_id", "audience", "restricted_roles", "category", "goal_id", "locked_at", "created_by")
  values (v_from."tenant_id", v_from."type", v_from."title", v_body, auth.uid(), v_from."id", v_from."audience", v_from."restricted_roles", v_from."category", v_from."goal_id", case when v_from."type"::text = any ('{note,report}'::text[]) then now() + interval '24 hours' end, auth.uid())
  returning "id" into v_id;
  insert into "app_private"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select k."tenant_id", v_id, k."subject_type", k."subject_id", k."position"
  from "app_private"."engagement_subjects" k where k."engagement_id" = v_from."id";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "app_private"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."amend_engagement"(uuid, text) from public, anon;
grant execute on function "app_private"."amend_engagement"(uuid, text) to authenticated, service_role;

-- Flags an engagement as entered in error with a reason. The row stays, so
-- the record keeps what was written; the flag also locks it. The author, the
-- owner and members with activities.manage may mark it.
create or replace function "app_private"."mark_engagement_error"(engagement uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := mark_engagement_error.engagement;
  v_reason text := nullif(trim(mark_engagement_error.reason), '');
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."engagement_id" = mark_engagement_error.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_reason is null then
    raise exception 'say why the engagement is in error' using errcode = '23502', hint = 'ENGAGEMENT_REASON_REQUIRED';
  end if;
  if exists (select 1 from "app_private"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."marked_error_at" is not null) then
    raise exception 'the engagement is already marked in error' using errcode = '55000', hint = 'ENGAGEMENT_ALREADY_MARKED_ERROR';
  end if;
  update "app_private"."engagements" x set
    "marked_error_at" = now(),
    "marked_error_by" = auth.uid(),
    "marked_error_reason" = v_reason,
    "locked_at" = least(coalesce(x."locked_at", now()), now())
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type"::text into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "app_private"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "app_private"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."mark_engagement_error"(uuid, text) from public, anon;
grant execute on function "app_private"."mark_engagement_error"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."engagements";
drop policy if exists bsb_tenant_scope_select on "app_private"."engagements";
create policy bsb_tenant_scope_select on "app_private"."engagements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "app_private"."engagement_subjects" lx where lx."engagement_id" = "id")
  or exists (select 1 from "app_private"."engagement_subjects" lx where lx."engagement_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "app_private"."engagement_subjects" nx where nx."engagement_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."engagements";
create policy bsb_tenant_scope_insert on "app_private"."engagements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."engagements";
create policy bsb_tenant_scope_update on "app_private"."engagements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."engagements";
create policy bsb_tenant_scope_delete on "app_private"."engagements" as restrictive
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
-- @bsb-hash sha256:fc154848e88c3534185b137ea33c45a51323b129c973dbf0c81ce9080a1f7c52
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('activities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block activities@1 managed
-- @bsb-hash sha256:8f142b71d8baa66eadddb0b1a093e8011b76b34099237c592e63bad528034e9d
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagements";
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
create table if not exists "better_supabase"."engagements" (
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
create index if not exists engagements_owner_open_idx on "better_supabase"."engagements" ("tenant_id", "owner_user_id", "due_at") where "done_at" is null;
create index if not exists engagements_tenant_created_idx on "better_supabase"."engagements" ("tenant_id", "created_at" desc);
create unique index if not exists engagements_external_ref_idx on "better_supabase"."engagements" ("tenant_id", "external_ref") where "external_ref" is not null;
-- Progress notes: who reads an engagement, when it locks, its addenda and the
-- in-error flag.
alter table "better_supabase"."engagements" add column if not exists "audience" text not null default 'team' check ("audience" in ('team', 'subject', 'restricted'));
alter table "better_supabase"."engagements" add column if not exists "restricted_roles" text[];
alter table "better_supabase"."engagements" add column if not exists "category" text check (length("category") between 1 and 63);
alter table "better_supabase"."engagements" add column if not exists "locked_at" timestamptz;
alter table "better_supabase"."engagements" add column if not exists "amends_id" uuid references "better_supabase"."engagements" ("id") on delete cascade;
alter table "better_supabase"."engagements" add column if not exists "goal_id" uuid;
alter table "better_supabase"."engagements" add column if not exists "marked_error_at" timestamptz;
alter table "better_supabase"."engagements" add column if not exists "marked_error_by" uuid;
alter table "better_supabase"."engagements" add column if not exists "marked_error_reason" text check (length("marked_error_reason") between 1 and 2000);
create index if not exists engagements_amends_idx on "better_supabase"."engagements" ("amends_id");
alter table "better_supabase"."engagements" enable row level security;
revoke all on "better_supabase"."engagements" from public, anon, authenticated;
grant select on "better_supabase"."engagements" to authenticated;
grant all on "better_supabase"."engagements" to service_role;
create table if not exists "better_supabase"."engagement_subjects" (
  "tenant_id" uuid not null,
  "engagement_id" uuid not null references "better_supabase"."engagements" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "position" integer not null default 1,
  primary key ("engagement_id", "subject_type", "subject_id")
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
drop policy if exists engagements_read on "better_supabase"."engagements";
create policy engagements_read on "better_supabase"."engagements"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."engagement_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))));

-- Logs an engagement on the records in subjects ([{ type, id }], the first
-- is its main record). attrs: type, title, body, outcome, ownerId, dueAt,
-- doneAt, durationSeconds, externalRef and fields (the extra columns by
-- name). A known externalRef updates instead.
create or replace function "better_supabase"."log_engagement"(tenant uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant uuid := log_engagement.tenant;
  v_type text := log_engagement.attrs ->> 'type';
  v_title text := nullif(trim(log_engagement.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_engagement.attrs ->> 'ownerId', '')::uuid, auth.uid());
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
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ENGAGEMENT_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ENGAGEMENT_TITLE_REQUIRED';
  end if;
  if nullif(log_engagement.attrs ->> 'audience', '') is not null and not (log_engagement.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if log_engagement.attrs ? 'restrictedRoles' and jsonb_typeof(log_engagement.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if nullif(log_engagement.attrs ->> 'category', '') is not null and not (log_engagement.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ENGAGEMENT_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."tenant_id" = v_tenant and x."external_ref" = log_engagement.attrs ->> 'externalRef' and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_engagement_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_engagement.tenant, log_engagement.attrs, log_engagement.subjects;
    end if;
  end;
  insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by", "audience", "restricted_roles", "category", "locked_at", "goal_id")
  values (v_tenant, v_type, v_title, log_engagement.attrs ->> 'body', log_engagement.attrs ->> 'outcome', v_owner, (log_engagement.attrs ->> 'dueAt')::timestamptz, (log_engagement.attrs ->> 'doneAt')::timestamptz, (log_engagement.attrs ->> 'durationSeconds')::integer, log_engagement.attrs ->> 'externalRef', auth.uid(), coalesce(nullif(log_engagement.attrs ->> 'audience', ''), 'team'), nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(log_engagement.attrs -> 'restrictedRoles') = 'array' then log_engagement.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}'), nullif(log_engagement.attrs ->> 'category', ''), case when v_type = any ('{note,report}'::text[]) then now() + interval '24 hours' end, nullif(log_engagement.attrs ->> 'goalId', '')::uuid)
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at", "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_engagement_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."log_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."log_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys attrs names, and the records when subjects isn't null.
-- The author, the owner and members with engagements.manage may edit.
create or replace function "better_supabase"."update_engagement"(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := update_engagement.engagement;
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
  from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if update_engagement.attrs ? 'type' and not (update_engagement.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  if nullif(update_engagement.attrs ->> 'audience', '') is not null and not (update_engagement.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if update_engagement.attrs ? 'restrictedRoles' and jsonb_typeof(update_engagement.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if nullif(update_engagement.attrs ->> 'category', '') is not null and not (update_engagement.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ENGAGEMENT_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  update "better_supabase"."engagements" x set
    "type" = coalesce(update_engagement.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_engagement.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_engagement.attrs ? 'body' then update_engagement.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_engagement.attrs ? 'outcome' then update_engagement.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_engagement.attrs ? 'externalRef' then update_engagement.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_engagement.attrs ? 'ownerId' then nullif(update_engagement.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_engagement.attrs ? 'dueAt' then (update_engagement.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_engagement.attrs ? 'doneAt' then (update_engagement.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_engagement.attrs ? 'durationSeconds' then (update_engagement.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "audience" = case when update_engagement.attrs ? 'audience' then coalesce(nullif(update_engagement.attrs ->> 'audience', ''), 'team') else x."audience" end,
    "restricted_roles" = case when update_engagement.attrs ? 'restrictedRoles' then nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(update_engagement.attrs -> 'restrictedRoles') = 'array' then update_engagement.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}') else x."restricted_roles" end,
    "category" = case when update_engagement.attrs ? 'category' then nullif(update_engagement.attrs ->> 'category', '') else x."category" end,
    "goal_id" = case when update_engagement.attrs ? 'goalId' then nullif(update_engagement.attrs ->> 'goalId', '')::uuid else x."goal_id" end,
    "locked_at" = case when update_engagement.attrs ? 'type' then coalesce(x."locked_at", case when update_engagement.attrs ->> 'type' = any ('{note,report}'::text[]) then x."created_at" + interval '24 hours' end) else x."locked_at" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_engagement.subjects is not null then
    
  if jsonb_typeof(coalesce(update_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."update_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."update_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Marks an engagement done now (done true) or open again.
create or replace function "better_supabase"."complete_engagement"(engagement uuid, done boolean, outcome text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := complete_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = complete_engagement.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  update "better_supabase"."engagements" x set
    "done_at" = case when complete_engagement.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_engagement.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if complete_engagement.done then
    null;
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."complete_engagement"(uuid, boolean, text) from public, anon;
grant execute on function "better_supabase"."complete_engagement"(uuid, boolean, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_engagement"(engagement uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = delete_engagement.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  delete from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_engagement"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_engagement"(uuid) to authenticated, service_role;

-- A record's engagements the caller can see, newest first: done ones by
-- when they happened, open ones by when they are due. before continues
-- after the last row of the previous page.
create or replace function "better_supabase"."engagements_of"(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, coalesce(x."done_at", x."due_at", x."created_at") as at, x."id" as id
    from "better_supabase"."engagements" x
    join "better_supabase"."engagement_subjects" k on k."engagement_id" = x."id"
    where k."subject_type" = engagements_of.subject_type and k."subject_id" = engagements_of.subject_id
      and (engagements_of.types is null or x."type" = any (engagements_of.types))
      and (engagements_of.before is null or coalesce(x."done_at", x."due_at", x."created_at") < engagements_of.before)
    order by at desc, id desc
    limit least(greatest(coalesce(engagements_of.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."engagements_of"(text, text, text[], timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."engagements_of"(text, text, text[], timestamptz, integer) to authenticated, service_role;

-- The next open engagement with a due time on a record, earliest first,
-- for a "next step" and an overdue flag; null when none is planned.
create or replace function "better_supabase"."next_engagement"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now())
  from "better_supabase"."engagements" x
  join "better_supabase"."engagement_subjects" k on k."engagement_id" = x."id"
  where k."subject_type" = next_engagement.subject_type and k."subject_id" = next_engagement.subject_id
    and x."done_at" is null and x."due_at" is not null
  order by x."due_at", x."id"
  limit 1
$$;
revoke execute on function "better_supabase"."next_engagement"(text, text) from public, anon;
grant execute on function "better_supabase"."next_engagement"(text, text) to authenticated, service_role;

-- A member's open engagements in a tenant, earliest due first: a task list.
create or replace function "better_supabase"."open_engagements"(tenant uuid, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.due nulls last, p.id), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, x."due_at" as due, x."id" as id
    from "better_supabase"."engagements" x
    where x."tenant_id" = open_engagements.tenant
      and x."owner_user_id" = coalesce(open_engagements.owner, auth.uid())
      and x."done_at" is null
      and (open_engagements.due_before is null or x."due_at" < open_engagements.due_before)
    order by x."due_at" nulls last, x."id"
    limit least(greatest(coalesce(open_engagements.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."open_engagements"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."open_engagements"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- Adds an addendum to an engagement the caller can read: a new engagement of
-- the same type, title, audience and records with body, pointing at it
-- through amends_id. A locked note changes this way only.
create or replace function "better_supabase"."amend_engagement"(engagement uuid, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from "better_supabase"."engagements";
  v_id uuid;
  v_body text := nullif(trim(amend_engagement.body), '');
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_from from "better_supabase"."engagements" x
  where x."id" = amend_engagement.engagement and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = x."id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = x."id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and (x."audience" <> 'restricted' or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or x."owner_user_id" = (select auth.uid()) or x."created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."engagement_id" = x."id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", x."restricted_roles"))));
  if v_from."id" is null then
    raise exception 'no such engagement you can read' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'activities.write'), false)) then
    raise exception 'not allowed to amend engagements' using errcode = '42501', hint = 'ENGAGEMENT_FORBIDDEN';
  end if;
  if v_body is null then
    raise exception 'an addendum needs a body' using errcode = '23502', hint = 'ENGAGEMENT_BODY_REQUIRED';
  end if;
  insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "owner_user_id", "amends_id", "audience", "restricted_roles", "category", "goal_id", "locked_at", "created_by")
  values (v_from."tenant_id", v_from."type", v_from."title", v_body, auth.uid(), v_from."id", v_from."audience", v_from."restricted_roles", v_from."category", v_from."goal_id", case when v_from."type"::text = any ('{note,report}'::text[]) then now() + interval '24 hours' end, auth.uid())
  returning "id" into v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select k."tenant_id", v_id, k."subject_type", k."subject_id", k."position"
  from "better_supabase"."engagement_subjects" k where k."engagement_id" = v_from."id";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."amend_engagement"(uuid, text) from public, anon;
grant execute on function "better_supabase"."amend_engagement"(uuid, text) to authenticated, service_role;

-- Flags an engagement as entered in error with a reason. The row stays, so
-- the record keeps what was written; the flag also locks it. The author, the
-- owner and members with activities.manage may mark it.
create or replace function "better_supabase"."mark_engagement_error"(engagement uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := mark_engagement_error.engagement;
  v_reason text := nullif(trim(mark_engagement_error.reason), '');
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = mark_engagement_error.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_reason is null then
    raise exception 'say why the engagement is in error' using errcode = '23502', hint = 'ENGAGEMENT_REASON_REQUIRED';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."marked_error_at" is not null) then
    raise exception 'the engagement is already marked in error' using errcode = '55000', hint = 'ENGAGEMENT_ALREADY_MARKED_ERROR';
  end if;
  update "better_supabase"."engagements" x set
    "marked_error_at" = now(),
    "marked_error_by" = auth.uid(),
    "marked_error_reason" = v_reason,
    "locked_at" = least(coalesce(x."locked_at", now()), now())
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type"::text into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."mark_engagement_error"(uuid, text) from public, anon;
grant execute on function "better_supabase"."mark_engagement_error"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."engagements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagements";
create policy bsb_tenant_scope_select on "better_supabase"."engagements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."engagement_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagements";
create policy bsb_tenant_scope_insert on "better_supabase"."engagements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagements";
create policy bsb_tenant_scope_update on "better_supabase"."engagements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagements";
create policy bsb_tenant_scope_delete on "better_supabase"."engagements" as restrictive
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

create or replace function "api"."log_engagement"(tenant uuid, attrs jsonb, subjects jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."log_engagement"($1, $2, $3) $$;
revoke execute on function "api"."log_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "api"."log_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."update_engagement"(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_engagement"($1, $2, $3) $$;
revoke execute on function "api"."update_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "api"."update_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."complete_engagement"(engagement uuid, done boolean, outcome text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_engagement"($1, $2, $3) $$;
revoke execute on function "api"."complete_engagement"(uuid, boolean, text) from public, anon;
grant execute on function "api"."complete_engagement"(uuid, boolean, text) to authenticated, service_role;

create or replace function "api"."delete_engagement"(engagement uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_engagement"($1) $$;
revoke execute on function "api"."delete_engagement"(uuid) from public, anon;
grant execute on function "api"."delete_engagement"(uuid) to authenticated, service_role;

create or replace function "api"."engagements_of"(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."engagements_of"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."engagements_of"(text, text, text[], timestamptz, integer) from public, anon;
grant execute on function "api"."engagements_of"(text, text, text[], timestamptz, integer) to authenticated, service_role;

create or replace function "api"."next_engagement"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."next_engagement"($1, $2) $$;
revoke execute on function "api"."next_engagement"(text, text) from public, anon;
grant execute on function "api"."next_engagement"(text, text) to authenticated, service_role;

create or replace function "api"."open_engagements"(tenant uuid, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."open_engagements"($1, $2, $3, $4) $$;
revoke execute on function "api"."open_engagements"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "api"."open_engagements"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."amend_engagement"(engagement uuid, body text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."amend_engagement"($1, $2) $$;
revoke execute on function "api"."amend_engagement"(uuid, text) from public, anon;
grant execute on function "api"."amend_engagement"(uuid, text) to authenticated, service_role;

create or replace function "api"."mark_engagement_error"(engagement uuid, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mark_engagement_error"($1, $2) $$;
revoke execute on function "api"."mark_engagement_error"(uuid, text) from public, anon;
grant execute on function "api"."mark_engagement_error"(uuid, text) to authenticated, service_role;

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
-- @bsb-hash sha256:fc154848e88c3534185b137ea33c45a51323b129c973dbf0c81ce9080a1f7c52
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('activities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block activities@1 managed
-- @bsb-hash sha256:e992e0038bc0ba7f5706c5e57c7dfb6421764ed0c2cb38ad47248642459be597
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagements";
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
-- better_supabase.engagements is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."engagements" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."engagements" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."engagements" add column if not exists "type" text;
alter table "better_supabase"."engagements" add column if not exists "title" text check (length("title") between 1 and 500);
alter table "better_supabase"."engagements" add column if not exists "body" text;
alter table "better_supabase"."engagements" add column if not exists "outcome" text;
alter table "better_supabase"."engagements" add column if not exists "owner_user_id" uuid;
alter table "better_supabase"."engagements" add column if not exists "due_at" timestamptz;
alter table "better_supabase"."engagements" add column if not exists "done_at" timestamptz;
alter table "better_supabase"."engagements" add column if not exists "duration_seconds" integer check ("duration_seconds" >= 0);
alter table "better_supabase"."engagements" add column if not exists "external_ref" text;
alter table "better_supabase"."engagements" add column if not exists "created_by" uuid;
alter table "better_supabase"."engagements" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."engagements" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists engagements_owner_open_idx on "better_supabase"."engagements" ("tenant_id", "owner_user_id", "due_at") where "done_at" is null;
create index if not exists engagements_tenant_created_idx on "better_supabase"."engagements" ("tenant_id", "created_at" desc);
create unique index if not exists engagements_external_ref_idx on "better_supabase"."engagements" ("tenant_id", "external_ref") where "external_ref" is not null;
-- Progress notes: who reads an engagement, when it locks, its addenda and the
-- in-error flag.
alter table "better_supabase"."engagements" add column if not exists "audience" text not null default 'team' check ("audience" in ('team', 'subject', 'restricted'));
alter table "better_supabase"."engagements" add column if not exists "restricted_roles" text[];
alter table "better_supabase"."engagements" add column if not exists "category" text check (length("category") between 1 and 63);
alter table "better_supabase"."engagements" add column if not exists "locked_at" timestamptz;
alter table "better_supabase"."engagements" add column if not exists "amends_id" uuid references "better_supabase"."engagements" ("id") on delete cascade;
alter table "better_supabase"."engagements" add column if not exists "goal_id" uuid;
alter table "better_supabase"."engagements" add column if not exists "marked_error_at" timestamptz;
alter table "better_supabase"."engagements" add column if not exists "marked_error_by" uuid;
alter table "better_supabase"."engagements" add column if not exists "marked_error_reason" text check (length("marked_error_reason") between 1 and 2000);
create index if not exists engagements_amends_idx on "better_supabase"."engagements" ("amends_id");
alter table "better_supabase"."engagements" enable row level security;
grant select on "better_supabase"."engagements" to authenticated;
grant all on "better_supabase"."engagements" to service_role;
-- better_supabase.engagement_subjects is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."engagement_subjects" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."engagement_subjects" add column if not exists "engagement_id" uuid references "better_supabase"."engagements" ("id") on delete cascade;
alter table "better_supabase"."engagement_subjects" add column if not exists "subject_type" text;
alter table "better_supabase"."engagement_subjects" add column if not exists "subject_id" text;
alter table "better_supabase"."engagement_subjects" add column if not exists "position" integer not null default 1;
create unique index if not exists "bsb_engagement_subjects_subject_key" on "better_supabase"."engagement_subjects" ("engagement_id", "subject_type", "subject_id");
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
drop policy if exists bsb_engagements_select on "better_supabase"."engagements";
create policy bsb_engagements_select on "better_supabase"."engagements"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."engagement_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))));

-- Logs an engagement on the records in subjects ([{ type, id }], the first
-- is its main record). attrs: type, title, body, outcome, ownerId, dueAt,
-- doneAt, durationSeconds, externalRef and fields (the extra columns by
-- name). A known externalRef updates instead.
create or replace function "better_supabase"."log_engagement"(tenant uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant uuid := log_engagement.tenant;
  v_type text := log_engagement.attrs ->> 'type';
  v_title text := nullif(trim(log_engagement.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_engagement.attrs ->> 'ownerId', '')::uuid, auth.uid());
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
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ENGAGEMENT_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ENGAGEMENT_TITLE_REQUIRED';
  end if;
  if nullif(log_engagement.attrs ->> 'audience', '') is not null and not (log_engagement.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if log_engagement.attrs ? 'restrictedRoles' and jsonb_typeof(log_engagement.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if nullif(log_engagement.attrs ->> 'category', '') is not null and not (log_engagement.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ENGAGEMENT_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."tenant_id" = v_tenant and x."external_ref" = log_engagement.attrs ->> 'externalRef' and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_engagement_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_engagement.tenant, log_engagement.attrs, log_engagement.subjects;
    end if;
  end;
  insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by", "audience", "restricted_roles", "category", "locked_at", "goal_id")
  values (v_tenant, better_supabase.as_column_type(v_type, (null::"better_supabase"."engagements")."type"), v_title, log_engagement.attrs ->> 'body', log_engagement.attrs ->> 'outcome', v_owner, (log_engagement.attrs ->> 'dueAt')::timestamptz, (log_engagement.attrs ->> 'doneAt')::timestamptz, (log_engagement.attrs ->> 'durationSeconds')::integer, log_engagement.attrs ->> 'externalRef', auth.uid(), coalesce(nullif(log_engagement.attrs ->> 'audience', ''), 'team'), nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(log_engagement.attrs -> 'restrictedRoles') = 'array' then log_engagement.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}'), nullif(log_engagement.attrs ->> 'category', ''), case when v_type = any ('{note,report}'::text[]) then now() + interval '24 hours' end, nullif(log_engagement.attrs ->> 'goalId', '')::uuid)
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at", "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_engagement_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'type', x."type", 'title', x."title", 'body', x."body", 'outcome', x."outcome", 'owner_user_id', x."owner_user_id", 'due_at', x."due_at", 'done_at', x."done_at", 'duration_seconds', x."duration_seconds", 'external_ref', x."external_ref", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at", 'audience', x."audience", 'restricted_roles', x."restricted_roles", 'category', x."category", 'locked_at', x."locked_at", 'amends_id', x."amends_id", 'goal_id', x."goal_id", 'marked_error_at', x."marked_error_at", 'marked_error_by', x."marked_error_by", 'marked_error_reason', x."marked_error_reason") || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."log_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."log_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys attrs names, and the records when subjects isn't null.
-- The author, the owner and members with engagements.manage may edit.
create or replace function "better_supabase"."update_engagement"(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := update_engagement.engagement;
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
  from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if update_engagement.attrs ? 'type' and not (update_engagement.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  if nullif(update_engagement.attrs ->> 'audience', '') is not null and not (update_engagement.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if update_engagement.attrs ? 'restrictedRoles' and jsonb_typeof(update_engagement.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if nullif(update_engagement.attrs ->> 'category', '') is not null and not (update_engagement.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ENGAGEMENT_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  update "better_supabase"."engagements" x set
    "type" = coalesce(better_supabase.as_column_type(update_engagement.attrs ->> 'type', (null::"better_supabase"."engagements")."type"), x."type"),
    "title" = coalesce(nullif(trim(update_engagement.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_engagement.attrs ? 'body' then update_engagement.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_engagement.attrs ? 'outcome' then update_engagement.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_engagement.attrs ? 'externalRef' then update_engagement.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_engagement.attrs ? 'ownerId' then nullif(update_engagement.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_engagement.attrs ? 'dueAt' then (update_engagement.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_engagement.attrs ? 'doneAt' then (update_engagement.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_engagement.attrs ? 'durationSeconds' then (update_engagement.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "audience" = case when update_engagement.attrs ? 'audience' then coalesce(nullif(update_engagement.attrs ->> 'audience', ''), 'team') else x."audience" end,
    "restricted_roles" = case when update_engagement.attrs ? 'restrictedRoles' then nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(update_engagement.attrs -> 'restrictedRoles') = 'array' then update_engagement.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}') else x."restricted_roles" end,
    "category" = case when update_engagement.attrs ? 'category' then nullif(update_engagement.attrs ->> 'category', '') else x."category" end,
    "goal_id" = case when update_engagement.attrs ? 'goalId' then nullif(update_engagement.attrs ->> 'goalId', '')::uuid else x."goal_id" end,
    "locked_at" = case when update_engagement.attrs ? 'type' then coalesce(x."locked_at", case when update_engagement.attrs ->> 'type' = any ('{note,report}'::text[]) then x."created_at" + interval '24 hours' end) else x."locked_at" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_engagement.subjects is not null then
    
  if jsonb_typeof(coalesce(update_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  null;
  return (select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'type', x."type", 'title', x."title", 'body', x."body", 'outcome', x."outcome", 'owner_user_id', x."owner_user_id", 'due_at', x."due_at", 'done_at', x."done_at", 'duration_seconds', x."duration_seconds", 'external_ref', x."external_ref", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at", 'audience', x."audience", 'restricted_roles', x."restricted_roles", 'category', x."category", 'locked_at', x."locked_at", 'amends_id', x."amends_id", 'goal_id', x."goal_id", 'marked_error_at', x."marked_error_at", 'marked_error_by', x."marked_error_by", 'marked_error_reason', x."marked_error_reason") || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."update_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."update_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Marks an engagement done now (done true) or open again.
create or replace function "better_supabase"."complete_engagement"(engagement uuid, done boolean, outcome text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := complete_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = complete_engagement.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  update "better_supabase"."engagements" x set
    "done_at" = case when complete_engagement.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_engagement.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if complete_engagement.done then
    null;
  end if;
  return (select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'type', x."type", 'title', x."title", 'body', x."body", 'outcome', x."outcome", 'owner_user_id', x."owner_user_id", 'due_at', x."due_at", 'done_at', x."done_at", 'duration_seconds', x."duration_seconds", 'external_ref', x."external_ref", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at", 'audience', x."audience", 'restricted_roles', x."restricted_roles", 'category', x."category", 'locked_at', x."locked_at", 'amends_id', x."amends_id", 'goal_id', x."goal_id", 'marked_error_at', x."marked_error_at", 'marked_error_by', x."marked_error_by", 'marked_error_reason', x."marked_error_reason") || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."complete_engagement"(uuid, boolean, text) from public, anon;
grant execute on function "better_supabase"."complete_engagement"(uuid, boolean, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_engagement"(engagement uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = delete_engagement.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  delete from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_engagement"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_engagement"(uuid) to authenticated, service_role;

-- A record's engagements the caller can see, newest first: done ones by
-- when they happened, open ones by when they are due. before continues
-- after the last row of the previous page.
create or replace function "better_supabase"."engagements_of"(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'type', x."type", 'title', x."title", 'body', x."body", 'outcome', x."outcome", 'owner_user_id', x."owner_user_id", 'due_at', x."due_at", 'done_at', x."done_at", 'duration_seconds', x."duration_seconds", 'external_ref', x."external_ref", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at", 'audience', x."audience", 'restricted_roles', x."restricted_roles", 'category', x."category", 'locked_at', x."locked_at", 'amends_id', x."amends_id", 'goal_id', x."goal_id", 'marked_error_at', x."marked_error_at", 'marked_error_by', x."marked_error_by", 'marked_error_reason', x."marked_error_reason") || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, coalesce(x."done_at", x."due_at", x."created_at") as at, x."id" as id
    from "better_supabase"."engagements" x
    join "better_supabase"."engagement_subjects" k on k."engagement_id" = x."id"
    where k."subject_type" = engagements_of.subject_type and k."subject_id" = engagements_of.subject_id
      and (engagements_of.types is null or x."type"::text = any (engagements_of.types))
      and (engagements_of.before is null or coalesce(x."done_at", x."due_at", x."created_at") < engagements_of.before)
    order by at desc, id desc
    limit least(greatest(coalesce(engagements_of.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."engagements_of"(text, text, text[], timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."engagements_of"(text, text, text[], timestamptz, integer) to authenticated, service_role;

-- The next open engagement with a due time on a record, earliest first,
-- for a "next step" and an overdue flag; null when none is planned.
create or replace function "better_supabase"."next_engagement"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'type', x."type", 'title', x."title", 'body', x."body", 'outcome', x."outcome", 'owner_user_id', x."owner_user_id", 'due_at', x."due_at", 'done_at', x."done_at", 'duration_seconds', x."duration_seconds", 'external_ref', x."external_ref", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at", 'audience', x."audience", 'restricted_roles', x."restricted_roles", 'category', x."category", 'locked_at', x."locked_at", 'amends_id', x."amends_id", 'goal_id', x."goal_id", 'marked_error_at', x."marked_error_at", 'marked_error_by', x."marked_error_by", 'marked_error_reason', x."marked_error_reason") || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now())
  from "better_supabase"."engagements" x
  join "better_supabase"."engagement_subjects" k on k."engagement_id" = x."id"
  where k."subject_type" = next_engagement.subject_type and k."subject_id" = next_engagement.subject_id
    and x."done_at" is null and x."due_at" is not null
  order by x."due_at", x."id"
  limit 1
$$;
revoke execute on function "better_supabase"."next_engagement"(text, text) from public, anon;
grant execute on function "better_supabase"."next_engagement"(text, text) to authenticated, service_role;

-- A member's open engagements in a tenant, earliest due first: a task list.
create or replace function "better_supabase"."open_engagements"(tenant uuid, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.due nulls last, p.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'type', x."type", 'title', x."title", 'body', x."body", 'outcome', x."outcome", 'owner_user_id', x."owner_user_id", 'due_at', x."due_at", 'done_at', x."done_at", 'duration_seconds', x."duration_seconds", 'external_ref', x."external_ref", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at", 'audience', x."audience", 'restricted_roles', x."restricted_roles", 'category', x."category", 'locked_at', x."locked_at", 'amends_id', x."amends_id", 'goal_id', x."goal_id", 'marked_error_at', x."marked_error_at", 'marked_error_by', x."marked_error_by", 'marked_error_reason', x."marked_error_reason") || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, x."due_at" as due, x."id" as id
    from "better_supabase"."engagements" x
    where x."tenant_id" = open_engagements.tenant
      and x."owner_user_id" = coalesce(open_engagements.owner, auth.uid())
      and x."done_at" is null
      and (open_engagements.due_before is null or x."due_at" < open_engagements.due_before)
    order by x."due_at" nulls last, x."id"
    limit least(greatest(coalesce(open_engagements.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."open_engagements"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."open_engagements"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- Adds an addendum to an engagement the caller can read: a new engagement of
-- the same type, title, audience and records with body, pointing at it
-- through amends_id. A locked note changes this way only.
create or replace function "better_supabase"."amend_engagement"(engagement uuid, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from "better_supabase"."engagements";
  v_id uuid;
  v_body text := nullif(trim(amend_engagement.body), '');
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_from from "better_supabase"."engagements" x
  where x."id" = amend_engagement.engagement and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = x."id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = x."id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and (x."audience" <> 'restricted' or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or x."owner_user_id" = (select auth.uid()) or x."created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."engagement_id" = x."id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", x."restricted_roles"))));
  if v_from."id" is null then
    raise exception 'no such engagement you can read' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'activities.write'), false)) then
    raise exception 'not allowed to amend engagements' using errcode = '42501', hint = 'ENGAGEMENT_FORBIDDEN';
  end if;
  if v_body is null then
    raise exception 'an addendum needs a body' using errcode = '23502', hint = 'ENGAGEMENT_BODY_REQUIRED';
  end if;
  insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "owner_user_id", "amends_id", "audience", "restricted_roles", "category", "goal_id", "locked_at", "created_by")
  values (v_from."tenant_id", v_from."type", v_from."title", v_body, auth.uid(), v_from."id", v_from."audience", v_from."restricted_roles", v_from."category", v_from."goal_id", case when v_from."type"::text = any ('{note,report}'::text[]) then now() + interval '24 hours' end, auth.uid())
  returning "id" into v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select k."tenant_id", v_id, k."subject_type", k."subject_id", k."position"
  from "better_supabase"."engagement_subjects" k where k."engagement_id" = v_from."id";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  return (select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'type', x."type", 'title', x."title", 'body', x."body", 'outcome', x."outcome", 'owner_user_id', x."owner_user_id", 'due_at', x."due_at", 'done_at', x."done_at", 'duration_seconds', x."duration_seconds", 'external_ref', x."external_ref", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at", 'audience', x."audience", 'restricted_roles', x."restricted_roles", 'category', x."category", 'locked_at', x."locked_at", 'amends_id', x."amends_id", 'goal_id', x."goal_id", 'marked_error_at', x."marked_error_at", 'marked_error_by', x."marked_error_by", 'marked_error_reason', x."marked_error_reason") || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."amend_engagement"(uuid, text) from public, anon;
grant execute on function "better_supabase"."amend_engagement"(uuid, text) to authenticated, service_role;

-- Flags an engagement as entered in error with a reason. The row stays, so
-- the record keeps what was written; the flag also locks it. The author, the
-- owner and members with activities.manage may mark it.
create or replace function "better_supabase"."mark_engagement_error"(engagement uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := mark_engagement_error.engagement;
  v_reason text := nullif(trim(mark_engagement_error.reason), '');
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = mark_engagement_error.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_reason is null then
    raise exception 'say why the engagement is in error' using errcode = '23502', hint = 'ENGAGEMENT_REASON_REQUIRED';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."marked_error_at" is not null) then
    raise exception 'the engagement is already marked in error' using errcode = '55000', hint = 'ENGAGEMENT_ALREADY_MARKED_ERROR';
  end if;
  update "better_supabase"."engagements" x set
    "marked_error_at" = now(),
    "marked_error_by" = auth.uid(),
    "marked_error_reason" = v_reason,
    "locked_at" = least(coalesce(x."locked_at", now()), now())
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type"::text into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  null;
  return (select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'type', x."type", 'title', x."title", 'body', x."body", 'outcome', x."outcome", 'owner_user_id', x."owner_user_id", 'due_at', x."due_at", 'done_at', x."done_at", 'duration_seconds', x."duration_seconds", 'external_ref', x."external_ref", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at", 'audience', x."audience", 'restricted_roles', x."restricted_roles", 'category', x."category", 'locked_at', x."locked_at", 'amends_id', x."amends_id", 'goal_id', x."goal_id", 'marked_error_at', x."marked_error_at", 'marked_error_by', x."marked_error_by", 'marked_error_reason', x."marked_error_reason") || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."mark_engagement_error"(uuid, text) from public, anon;
grant execute on function "better_supabase"."mark_engagement_error"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."engagements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagements";
create policy bsb_tenant_scope_select on "better_supabase"."engagements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."engagement_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagements";
create policy bsb_tenant_scope_insert on "better_supabase"."engagements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagements";
create policy bsb_tenant_scope_update on "better_supabase"."engagements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagements";
create policy bsb_tenant_scope_delete on "better_supabase"."engagements" as restrictive
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
-- @bsb-hash sha256:fc154848e88c3534185b137ea33c45a51323b129c973dbf0c81ce9080a1f7c52
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('activities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block activities@1 managed
-- @bsb-hash sha256:c50d869f94297a3fc0d52e2fe966726061f5616f9b04c91d3db64c81b023437d
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagements";
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
create table if not exists "better_supabase"."engagements" (
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
create index if not exists engagements_owner_open_idx on "better_supabase"."engagements" ("org_id", "owner_user_id", "due_at") where "done_at" is null;
create index if not exists engagements_tenant_created_idx on "better_supabase"."engagements" ("org_id", "created_at" desc);
create unique index if not exists engagements_external_ref_idx on "better_supabase"."engagements" ("org_id", "external_ref") where "external_ref" is not null;
-- Progress notes: who reads an engagement, when it locks, its addenda and the
-- in-error flag.
alter table "better_supabase"."engagements" add column if not exists "audience" text not null default 'team' check ("audience" in ('team', 'subject', 'restricted'));
alter table "better_supabase"."engagements" add column if not exists "restricted_roles" text[];
alter table "better_supabase"."engagements" add column if not exists "category" text check (length("category") between 1 and 63);
alter table "better_supabase"."engagements" add column if not exists "locked_at" timestamptz;
alter table "better_supabase"."engagements" add column if not exists "amends_id" uuid references "better_supabase"."engagements" ("id") on delete cascade;
alter table "better_supabase"."engagements" add column if not exists "goal_id" uuid;
alter table "better_supabase"."engagements" add column if not exists "marked_error_at" timestamptz;
alter table "better_supabase"."engagements" add column if not exists "marked_error_by" uuid;
alter table "better_supabase"."engagements" add column if not exists "marked_error_reason" text check (length("marked_error_reason") between 1 and 2000);
create index if not exists engagements_amends_idx on "better_supabase"."engagements" ("amends_id");
alter table "better_supabase"."engagements" enable row level security;
revoke all on "better_supabase"."engagements" from public, anon, authenticated;
grant select on "better_supabase"."engagements" to authenticated;
grant all on "better_supabase"."engagements" to service_role;
create table if not exists "better_supabase"."engagement_subjects" (
  "org_id" uuid not null,
  "engagement_id" uuid not null references "better_supabase"."engagements" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "position" integer not null default 1,
  primary key ("engagement_id", "subject_type", "subject_id")
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
drop policy if exists engagements_read on "better_supabase"."engagements";
create policy engagements_read on "better_supabase"."engagements"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "org_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."engagement_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))));

-- Logs an engagement on the records in subjects ([{ type, id }], the first
-- is its main record). attrs: type, title, body, outcome, ownerId, dueAt,
-- doneAt, durationSeconds, externalRef and fields (the extra columns by
-- name). A known externalRef updates instead.
create or replace function "better_supabase"."log_engagement"(tenant uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant uuid := log_engagement.tenant;
  v_type text := log_engagement.attrs ->> 'type';
  v_title text := nullif(trim(log_engagement.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_engagement.attrs ->> 'ownerId', '')::uuid, auth.uid());
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
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ENGAGEMENT_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ENGAGEMENT_TITLE_REQUIRED';
  end if;
  if nullif(log_engagement.attrs ->> 'audience', '') is not null and not (log_engagement.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if log_engagement.attrs ? 'restrictedRoles' and jsonb_typeof(log_engagement.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if nullif(log_engagement.attrs ->> 'category', '') is not null and not (log_engagement.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ENGAGEMENT_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."org_id" = v_tenant and x."external_ref" = log_engagement.attrs ->> 'externalRef' and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_engagement_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_engagement.tenant, log_engagement.attrs, log_engagement.subjects;
    end if;
  end;
  insert into "better_supabase"."engagements" ("org_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by", "audience", "restricted_roles", "category", "locked_at", "goal_id")
  values (v_tenant, v_type, v_title, log_engagement.attrs ->> 'body', log_engagement.attrs ->> 'outcome', v_owner, (log_engagement.attrs ->> 'dueAt')::timestamptz, (log_engagement.attrs ->> 'doneAt')::timestamptz, (log_engagement.attrs ->> 'durationSeconds')::integer, log_engagement.attrs ->> 'externalRef', auth.uid(), coalesce(nullif(log_engagement.attrs ->> 'audience', ''), 'team'), nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(log_engagement.attrs -> 'restrictedRoles') = 'array' then log_engagement.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}'), nullif(log_engagement.attrs ->> 'category', ''), case when v_type = any ('{note,report}'::text[]) then now() + interval '24 hours' end, nullif(log_engagement.attrs ->> 'goalId', '')::uuid)
  on conflict ("org_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at", "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("org_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_engagement_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."log_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."log_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys attrs names, and the records when subjects isn't null.
-- The author, the owner and members with engagements.manage may edit.
create or replace function "better_supabase"."update_engagement"(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := update_engagement.engagement;
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
  from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'activities.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if update_engagement.attrs ? 'type' and not (update_engagement.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  if nullif(update_engagement.attrs ->> 'audience', '') is not null and not (update_engagement.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if update_engagement.attrs ? 'restrictedRoles' and jsonb_typeof(update_engagement.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ENGAGEMENT_AUDIENCE_INVALID';
  end if;
  if nullif(update_engagement.attrs ->> 'category', '') is not null and not (update_engagement.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ENGAGEMENT_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  update "better_supabase"."engagements" x set
    "type" = coalesce(update_engagement.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_engagement.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_engagement.attrs ? 'body' then update_engagement.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_engagement.attrs ? 'outcome' then update_engagement.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_engagement.attrs ? 'externalRef' then update_engagement.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_engagement.attrs ? 'ownerId' then nullif(update_engagement.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_engagement.attrs ? 'dueAt' then (update_engagement.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_engagement.attrs ? 'doneAt' then (update_engagement.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_engagement.attrs ? 'durationSeconds' then (update_engagement.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "audience" = case when update_engagement.attrs ? 'audience' then coalesce(nullif(update_engagement.attrs ->> 'audience', ''), 'team') else x."audience" end,
    "restricted_roles" = case when update_engagement.attrs ? 'restrictedRoles' then nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(update_engagement.attrs -> 'restrictedRoles') = 'array' then update_engagement.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}') else x."restricted_roles" end,
    "category" = case when update_engagement.attrs ? 'category' then nullif(update_engagement.attrs ->> 'category', '') else x."category" end,
    "goal_id" = case when update_engagement.attrs ? 'goalId' then nullif(update_engagement.attrs ->> 'goalId', '')::uuid else x."goal_id" end,
    "locked_at" = case when update_engagement.attrs ? 'type' then coalesce(x."locked_at", case when update_engagement.attrs ->> 'type' = any ('{note,report}'::text[]) then x."created_at" + interval '24 hours' end) else x."locked_at" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_engagement.subjects is not null then
    
  if jsonb_typeof(coalesce(update_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("org_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."update_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."update_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Marks an engagement done now (done true) or open again.
create or replace function "better_supabase"."complete_engagement"(engagement uuid, done boolean, outcome text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := complete_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = complete_engagement.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  update "better_supabase"."engagements" x set
    "done_at" = case when complete_engagement.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_engagement.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'activities.manage'), false))
  returning x."org_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if complete_engagement.done then
    null;
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."complete_engagement"(uuid, boolean, text) from public, anon;
grant execute on function "better_supabase"."complete_engagement"(uuid, boolean, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_engagement"(engagement uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = delete_engagement.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_engagement instead' using errcode = '55000', hint = 'ENGAGEMENT_LOCKED';
  end if;
  delete from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'activities.manage'), false))
  returning x."org_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_engagement"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_engagement"(uuid) to authenticated, service_role;

-- A record's engagements the caller can see, newest first: done ones by
-- when they happened, open ones by when they are due. before continues
-- after the last row of the previous page.
create or replace function "better_supabase"."engagements_of"(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, coalesce(x."done_at", x."due_at", x."created_at") as at, x."id" as id
    from "better_supabase"."engagements" x
    join "better_supabase"."engagement_subjects" k on k."engagement_id" = x."id"
    where k."subject_type" = engagements_of.subject_type and k."subject_id" = engagements_of.subject_id
      and (engagements_of.types is null or x."type" = any (engagements_of.types))
      and (engagements_of.before is null or coalesce(x."done_at", x."due_at", x."created_at") < engagements_of.before)
    order by at desc, id desc
    limit least(greatest(coalesce(engagements_of.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."engagements_of"(text, text, text[], timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."engagements_of"(text, text, text[], timestamptz, integer) to authenticated, service_role;

-- The next open engagement with a due time on a record, earliest first,
-- for a "next step" and an overdue flag; null when none is planned.
create or replace function "better_supabase"."next_engagement"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now())
  from "better_supabase"."engagements" x
  join "better_supabase"."engagement_subjects" k on k."engagement_id" = x."id"
  where k."subject_type" = next_engagement.subject_type and k."subject_id" = next_engagement.subject_id
    and x."done_at" is null and x."due_at" is not null
  order by x."due_at", x."id"
  limit 1
$$;
revoke execute on function "better_supabase"."next_engagement"(text, text) from public, anon;
grant execute on function "better_supabase"."next_engagement"(text, text) to authenticated, service_role;

-- A member's open engagements in a tenant, earliest due first: a task list.
create or replace function "better_supabase"."open_engagements"(tenant uuid, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.due nulls last, p.id), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, x."due_at" as due, x."id" as id
    from "better_supabase"."engagements" x
    where x."org_id" = open_engagements.tenant
      and x."owner_user_id" = coalesce(open_engagements.owner, auth.uid())
      and x."done_at" is null
      and (open_engagements.due_before is null or x."due_at" < open_engagements.due_before)
    order by x."due_at" nulls last, x."id"
    limit least(greatest(coalesce(open_engagements.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."open_engagements"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."open_engagements"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- Adds an addendum to an engagement the caller can read: a new engagement of
-- the same type, title, audience and records with body, pointing at it
-- through amends_id. A locked note changes this way only.
create or replace function "better_supabase"."amend_engagement"(engagement uuid, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from "better_supabase"."engagements";
  v_id uuid;
  v_body text := nullif(trim(amend_engagement.body), '');
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_from from "better_supabase"."engagements" x
  where x."id" = amend_engagement.engagement and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."org_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = x."id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = x."id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and (x."audience" <> 'restricted' or x."org_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or x."owner_user_id" = (select auth.uid()) or x."created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."engagement_id" = x."id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", x."restricted_roles"))));
  if v_from."id" is null then
    raise exception 'no such engagement you can read' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."org_id", 'activities.write'), false)) then
    raise exception 'not allowed to amend engagements' using errcode = '42501', hint = 'ENGAGEMENT_FORBIDDEN';
  end if;
  if v_body is null then
    raise exception 'an addendum needs a body' using errcode = '23502', hint = 'ENGAGEMENT_BODY_REQUIRED';
  end if;
  insert into "better_supabase"."engagements" ("org_id", "type", "title", "body", "owner_user_id", "amends_id", "audience", "restricted_roles", "category", "goal_id", "locked_at", "created_by")
  values (v_from."org_id", v_from."type", v_from."title", v_body, auth.uid(), v_from."id", v_from."audience", v_from."restricted_roles", v_from."category", v_from."goal_id", case when v_from."type"::text = any ('{note,report}'::text[]) then now() + interval '24 hours' end, auth.uid())
  returning "id" into v_id;
  insert into "better_supabase"."engagement_subjects" ("org_id", "engagement_id", "subject_type", "subject_id", "position")
  select k."org_id", v_id, k."subject_type", k."subject_id", k."position"
  from "better_supabase"."engagement_subjects" k where k."engagement_id" = v_from."id";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."amend_engagement"(uuid, text) from public, anon;
grant execute on function "better_supabase"."amend_engagement"(uuid, text) to authenticated, service_role;

-- Flags an engagement as entered in error with a reason. The row stays, so
-- the record keeps what was written; the flag also locks it. The author, the
-- owner and members with activities.manage may mark it.
create or replace function "better_supabase"."mark_engagement_error"(engagement uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := mark_engagement_error.engagement;
  v_reason text := nullif(trim(mark_engagement_error.reason), '');
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = mark_engagement_error.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_reason is null then
    raise exception 'say why the engagement is in error' using errcode = '23502', hint = 'ENGAGEMENT_REASON_REQUIRED';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'activities.manage'), false)) and x."marked_error_at" is not null) then
    raise exception 'the engagement is already marked in error' using errcode = '55000', hint = 'ENGAGEMENT_ALREADY_MARKED_ERROR';
  end if;
  update "better_supabase"."engagements" x set
    "marked_error_at" = now(),
    "marked_error_by" = auth.uid(),
    "marked_error_reason" = v_reason,
    "locked_at" = least(coalesce(x."locked_at", now()), now())
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'activities.manage'), false))
  returning x."org_id", x."type"::text into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."mark_engagement_error"(uuid, text) from public, anon;
grant execute on function "better_supabase"."mark_engagement_error"(uuid, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."engagements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."engagements";
create policy bsb_tenant_scope_select on "better_supabase"."engagements" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "org_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_user_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."engagement_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."engagements";
create policy bsb_tenant_scope_insert on "better_supabase"."engagements" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."engagements";
create policy bsb_tenant_scope_update on "better_supabase"."engagements" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."engagements";
create policy bsb_tenant_scope_delete on "better_supabase"."engagements" as restrictive
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
-- @bsb-hash sha256:fc154848e88c3534185b137ea33c45a51323b129c973dbf0c81ce9080a1f7c52
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('activities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
