-- ==== schema supabase/schemas/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block activities@4 managed
-- @bsb-hash sha256:fbfaf4aca2476ef8c14ab8500aee76f963fd33879550333c61427c34a0e10a2d
-- Calls, emails, meetings, notes and tasks logged on one or more registered records, with an owner, a due time and an outcome, a record's timeline, its next step and a member's open tasks.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Calls, emails, meetings, notes and tasks logged on one or more records.
create table "better_supabase"."activities" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "type" text not null,
  "title" text not null constraint bsb_activities_title_check check (length("title") >= 1 and length("title") <= 500),
  "body" text,
  "outcome" text,
  "owner_id" uuid,
  "due_at" timestamptz,
  "done_at" timestamptz,
  "duration_seconds" integer constraint bsb_activities_duration_seconds_check check ("duration_seconds" >= 0),
  "external_ref" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index "activities_owner_open_idx" on "better_supabase"."activities" ("tenant_id", "owner_id", "due_at") where "done_at" is null;
create index "activities_tenant_created_idx" on "better_supabase"."activities" ("tenant_id", "created_at" desc);
create unique index "activities_external_ref_idx" on "better_supabase"."activities" ("tenant_id", "external_ref") where "external_ref" is not null;
-- Progress notes: who reads an activity, when it locks, its addenda and the
-- in-error flag.
alter table "better_supabase"."activities" add column "audience" text not null default 'team' constraint bsb_activities_audience_check check ("audience" in ('team', 'subject', 'restricted'));
alter table "better_supabase"."activities" add column "restricted_roles" text[];
alter table "better_supabase"."activities" add column "category" text constraint bsb_activities_category_check check (length("category") >= 1 and length("category") <= 63);
alter table "better_supabase"."activities" add column "locked_at" timestamptz;
alter table "better_supabase"."activities" add column "amends_id" uuid references "better_supabase"."activities" ("id") on delete cascade;
alter table "better_supabase"."activities" add column "goal_id" uuid;
alter table "better_supabase"."activities" add column "marked_error_at" timestamptz;
alter table "better_supabase"."activities" add column "marked_error_by" uuid;
alter table "better_supabase"."activities" add column "marked_error_reason" text constraint bsb_activities_marked_error_reason_check check (length("marked_error_reason") >= 1 and length("marked_error_reason") <= 2000);
create index "activities_amends_idx" on "better_supabase"."activities" ("amends_id");
alter table "better_supabase"."activities" enable row level security;
revoke all on "better_supabase"."activities" from public, anon, authenticated;
grant select on "better_supabase"."activities" to authenticated;
grant all on "better_supabase"."activities" to service_role;
create table "better_supabase"."activity_subjects" (
  "tenant_id" uuid not null,
  "activity_id" uuid not null references "better_supabase"."activities" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "position" integer not null default 1,
  primary key ("activity_id", "subject_type", "subject_id")
);
create index activity_subjects_subject_idx on "better_supabase"."activity_subjects" ("subject_type", "subject_id");
alter table "better_supabase"."activity_subjects" enable row level security;
revoke all on "better_supabase"."activity_subjects" from public, anon, authenticated;
grant select on "better_supabase"."activity_subjects" to authenticated;
grant all on "better_supabase"."activity_subjects" to service_role;
-- A link is visible when its record is; an activity when one of its
-- records is, or it has none. A guest of a record reads its subject notes.
create policy bsb_activity_subjects_read on "better_supabase"."activity_subjects"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));
create policy bsb_activities_read on "better_supabase"."activities"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."activity_subjects" lx where lx."activity_id" = "id")
  or exists (select 1 from "better_supabase"."activity_subjects" lx where lx."activity_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."activity_subjects" nx where nx."activity_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))));

-- Logs an activity on the records in subjects ([{ type, id }], the first
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
    raise exception 'not allowed to log activities' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown activity type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
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
    raise exception 'the activity is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_activity_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_activity.tenant, log_activity.attrs, log_activity.subjects;
    end if;
  end;
  insert into "better_supabase"."activities" ("tenant_id", "type", "title", "body", "outcome", "owner_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by", "audience", "restricted_roles", "category", "locked_at", "goal_id")
  values (v_tenant, v_type, v_title, log_activity.attrs ->> 'body', log_activity.attrs ->> 'outcome', v_owner, (log_activity.attrs ->> 'dueAt')::timestamptz, (log_activity.attrs ->> 'doneAt')::timestamptz, (log_activity.attrs ->> 'durationSeconds')::integer, log_activity.attrs ->> 'externalRef', auth.uid(), coalesce(nullif(log_activity.attrs ->> 'audience', ''), 'team'), nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(log_activity.attrs -> 'restrictedRoles') = 'array' then log_activity.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}'), nullif(log_activity.attrs ->> 'category', ''), case when v_type = any ('{note,report}'::text[]) then now() + interval '24 hours' end, nullif(log_activity.attrs ->> 'goalId', '')::uuid)
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at", "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  update "better_supabase"."activities" x set "app_note" = case when log_activity.attrs -> 'fields' ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."activities", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(log_activity.attrs -> 'fields') e where e.key in ('app_note'))) r
  where x."id" = v_id;
  
  if jsonb_typeof(coalesce(log_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."activity_subjects" x where x."activity_id" = v_id;
  insert into "better_supabase"."activity_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
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
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now(), 'fields', jsonb_build_object('app_note', x."app_note")) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."log_activity"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."log_activity"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys attrs names, and the records when subjects isn't null.
-- The author, the owner and members with activities.manage may edit.
create or replace function "better_supabase"."update_activity"(activity uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := update_activity.activity;
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
  select x."tenant_id", x."type", x."owner_id" into v_tenant, v_type, v_previous_owner
  from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
  if v_tenant is null then
    raise exception 'no such activity you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if update_activity.attrs ? 'type' and not (update_activity.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown activity type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
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
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the activity is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "better_supabase"."activities" x set
    "type" = coalesce(update_activity.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_activity.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_activity.attrs ? 'body' then update_activity.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_activity.attrs ? 'outcome' then update_activity.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_activity.attrs ? 'externalRef' then update_activity.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_id" = case when update_activity.attrs ? 'ownerId' then nullif(update_activity.attrs ->> 'ownerId', '')::uuid else x."owner_id" end,
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
  returning x."type", x."title", x."owner_id" into v_type, v_title, v_owner;
  update "better_supabase"."activities" x set "app_note" = case when update_activity.attrs -> 'fields' ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."activities", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(update_activity.attrs -> 'fields') e where e.key in ('app_note'))) r
  where x."id" = v_id;
  if update_activity.subjects is not null then
    
  if jsonb_typeof(coalesce(update_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."activity_subjects" x where x."activity_id" = v_id;
  insert into "better_supabase"."activity_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now(), 'fields', jsonb_build_object('app_note', x."app_note")) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."update_activity"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."update_activity"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Marks an activity done now (done true) or open again.
create or replace function "better_supabase"."complete_activity"(activity uuid, done boolean, outcome text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := complete_activity.activity;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = complete_activity.activity), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the activity is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "better_supabase"."activities" x set
    "done_at" = case when complete_activity.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_activity.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such activity you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if complete_activity.done then
    null;
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now(), 'fields', jsonb_build_object('app_note', x."app_note")) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."complete_activity"(uuid, boolean, text) from public, anon;
grant execute on function "better_supabase"."complete_activity"(uuid, boolean, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_activity"(activity uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_activity.activity;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = delete_activity.activity), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the activity is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  delete from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
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

-- A record's activities the caller can see, newest first: done ones by
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
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now(), 'fields', jsonb_build_object('app_note', x."app_note")) as value, coalesce(x."done_at", x."due_at", x."created_at") as at, x."id" as id
    from "better_supabase"."activities" x
    join "better_supabase"."activity_subjects" k on k."activity_id" = x."id"
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

-- The next open activity with a due time on a record, earliest first,
-- for a "next step" and an overdue flag; null when none is planned.
create or replace function "better_supabase"."next_activity"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now(), 'fields', jsonb_build_object('app_note', x."app_note"))
  from "better_supabase"."activities" x
  join "better_supabase"."activity_subjects" k on k."activity_id" = x."id"
  where k."subject_type" = next_activity.subject_type and k."subject_id" = next_activity.subject_id
    and x."done_at" is null and x."due_at" is not null
  order by x."due_at", x."id"
  limit 1
$$;
revoke execute on function "better_supabase"."next_activity"(text, text) from public, anon;
grant execute on function "better_supabase"."next_activity"(text, text) to authenticated, service_role;

-- A member's open activities in a tenant, earliest due first: a task list.
create or replace function "better_supabase"."open_activities"(tenant uuid, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.due nulls last, p.id), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now(), 'fields', jsonb_build_object('app_note', x."app_note")) as value, x."due_at" as due, x."id" as id
    from "better_supabase"."activities" x
    where x."tenant_id" = open_activities.tenant
      and x."owner_id" = coalesce(open_activities.owner, auth.uid())
      and x."done_at" is null
      and (open_activities.due_before is null or x."due_at" < open_activities.due_before)
    order by x."due_at" nulls last, x."id"
    limit least(greatest(coalesce(open_activities.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."open_activities"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."open_activities"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- Adds an addendum to an activity the caller can read: a new activity of
-- the same type, title, audience and records with body, pointing at it
-- through amends_id. A locked note changes this way only.
create or replace function "better_supabase"."amend_activity"(activity uuid, body text)
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
  where x."id" = amend_activity.activity and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."activity_subjects" lx where lx."activity_id" = x."id")
  or exists (select 1 from "better_supabase"."activity_subjects" lx where lx."activity_id" = x."id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and (x."audience" <> 'restricted' or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or x."owner_id" = (select auth.uid()) or x."created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."activity_subjects" nx where nx."activity_id" = x."id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", x."restricted_roles"))));
  if v_from."id" is null then
    raise exception 'no such activity you can read' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'activities.write'), false)) then
    raise exception 'not allowed to amend activities' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_body is null then
    raise exception 'an addendum needs a body' using errcode = '23502', hint = 'ACTIVITY_BODY_REQUIRED';
  end if;
  insert into "better_supabase"."activities" ("tenant_id", "type", "title", "body", "owner_id", "amends_id", "audience", "restricted_roles", "category", "goal_id", "locked_at", "created_by")
  values (v_from."tenant_id", v_from."type", v_from."title", v_body, auth.uid(), v_from."id", v_from."audience", v_from."restricted_roles", v_from."category", v_from."goal_id", case when v_from."type"::text = any ('{note,report}'::text[]) then now() + interval '24 hours' end, auth.uid())
  returning "id" into v_id;
  insert into "better_supabase"."activity_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select k."tenant_id", v_id, k."subject_type", k."subject_id", k."position"
  from "better_supabase"."activity_subjects" k where k."activity_id" = v_from."id";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now(), 'fields', jsonb_build_object('app_note', x."app_note")) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."amend_activity"(uuid, text) from public, anon;
grant execute on function "better_supabase"."amend_activity"(uuid, text) to authenticated, service_role;

-- Flags an activity as entered in error with a reason. The row stays, so
-- the record keeps what was written; the flag also locks it. The author, the
-- owner and members with activities.manage may mark it.
create or replace function "better_supabase"."mark_activity_error"(activity uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := mark_activity_error.activity;
  v_reason text := nullif(trim(mark_activity_error.reason), '');
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = mark_activity_error.activity), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_reason is null then
    raise exception 'say why the activity is in error' using errcode = '23502', hint = 'ACTIVITY_REASON_REQUIRED';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."marked_error_at" is not null) then
    raise exception 'the activity is already marked in error' using errcode = '55000', hint = 'ACTIVITY_ALREADY_MARKED_ERROR';
  end if;
  update "better_supabase"."activities" x set
    "marked_error_at" = now(),
    "marked_error_by" = auth.uid(),
    "marked_error_reason" = v_reason,
    "locked_at" = least(coalesce(x."locked_at", now()), now())
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type"::text into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such activity you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now(), 'fields', jsonb_build_object('app_note', x."app_note")) from "better_supabase"."activities" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."mark_activity_error"(uuid, text) from public, anon;
grant execute on function "better_supabase"."mark_activity_error"(uuid, text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."activities" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."activity_subjects" lx where lx."activity_id" = "id")
  or exists (select 1 from "better_supabase"."activity_subjects" lx where lx."activity_id" = "id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and ("audience" <> 'restricted' or "tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or "owner_id" = (select auth.uid()) or "created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."activity_subjects" nx where nx."activity_id" = "id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", "restricted_roles"))))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."activities" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."activities" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."activities" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."activity_subjects" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."activity_subjects" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."activity_subjects" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."activity_subjects" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_094_activities.sql
-- better-supabase module: activities
-- @bsb-block-data activities
-- @bsb-hash sha256:54603535a3ea5c52d46bd8813285bc20005672ef10d2ca005ee49b694b639d5e
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('activities', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
