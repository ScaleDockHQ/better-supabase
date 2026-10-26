-- ==== schema supabase/schemas/900_better_supabase_128_courses.sql
-- better-supabase module: courses
-- @bsb-block courses@1 managed
-- @bsb-hash sha256:c30b38cfadf875db0c9eca1f55c51ad43f87a90cd3542a7364826faaa7c6dc37
-- Courses of modules and lessons ordered by rank keys, with quiz lessons graded by forms, per-lesson progress, completion and certificates. Each course runs as an enrollment program, so learners enroll through enrollments.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."courses";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."courses";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."courses";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."courses";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."courses";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."course_modules";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."course_modules";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."course_modules";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."course_modules";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."course_modules";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."course_lessons";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."course_lessons";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."course_lessons";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."course_lessons";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."course_lessons";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."course_lesson_progress";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."course_lesson_progress";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."course_lesson_progress";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."course_lesson_progress";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."course_lesson_progress";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."course_certificates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."course_certificates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."course_certificates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."course_certificates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."course_certificates";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Courses of modules and lessons ordered by rank keys. Each course runs as
-- the enrollment program course:<id>, whose steps are its required lessons.
create table if not exists "better_supabase"."courses" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9-]{0,62}$'),
  "title" text not null check (length("title") between 1 and 200),
  "summary" text check ("summary" is null or length("summary") <= 2000),
  "status" text not null default 'draft' check ("status" in ('draft', 'published', 'archived')),
  "issues_certificate" boolean not null default true,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);
alter table "better_supabase"."courses" add column if not exists "app_note" text;

create table if not exists "better_supabase"."course_modules" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "course_id" uuid not null references "better_supabase"."courses" ("id") on delete cascade,
  "title" text not null check (length("title") between 1 and 200),
  -- A fractional rank key (ADR 0021): modules sort by it within the course.
  "rank" text collate "C" not null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "course_modules_parent_idx" on "better_supabase"."course_modules" ("course_id", "rank");

create table if not exists "better_supabase"."course_lessons" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "course_id" uuid not null references "better_supabase"."courses" ("id") on delete cascade,
  "module_id" uuid not null references "better_supabase"."course_modules" ("id") on delete cascade,
  "title" text not null check (length("title") between 1 and 200),
  "kind" text not null default 'content' check ("kind" in ('content', 'video', 'quiz')),
  -- The lesson's content, such as a rich-text document; only enrolled
  -- learners and the course's managers read it.
  "body" jsonb,
  "media_url" text check ("media_url" is null or ("media_url" ~ '^https?://' and length("media_url") <= 2000)),
  -- The forms form a quiz lesson grades; a passed submission completes it.
  "form_id" uuid,
  -- Required lessons are the steps of the course's enrollment program.
  "required" boolean not null default true,
  "duration_minutes" integer check ("duration_minutes" is null or "duration_minutes" between 1 and 10000),
  "rank" text collate "C" not null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("kind" = 'quiz') = ("form_id" is not null))
);
create index if not exists "course_lessons_module_idx" on "better_supabase"."course_lessons" ("module_id", "rank");
create index if not exists "course_lessons_parent_idx" on "better_supabase"."course_lessons" ("course_id");
create index if not exists "course_lessons_form_idx" on "better_supabase"."course_lessons" ("form_id") where "form_id" is not null;

-- A learner's state in one lesson of the course they are enrolled in. The
-- enrollment's steps hold the completed required lessons; this holds when
-- each lesson started and finished, and a quiz's attempts and grade.
create table if not exists "better_supabase"."course_lesson_progress" (
  "enrollment_id" uuid not null references "better_supabase"."enrollments" ("id") on delete cascade,
  "lesson_id" uuid not null references "better_supabase"."course_lessons" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "course_id" uuid not null references "better_supabase"."courses" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "started_at" timestamptz not null default now(),
  "completed_at" timestamptz,
  "attempts" integer not null default 0 check ("attempts" >= 0),
  "submission_id" uuid,
  "score" numeric,
  "max_score" numeric,
  "passed" boolean,
  "updated_at" timestamptz not null default now(),
  constraint "course_lesson_progress_pkey" primary key ("enrollment_id", "lesson_id")
);
create index if not exists "course_lesson_progress_lesson_idx" on "better_supabase"."course_lesson_progress" ("lesson_id");
create index if not exists "course_lesson_progress_parent_idx" on "better_supabase"."course_lesson_progress" ("course_id");
create index if not exists "course_lesson_progress_user_idx" on "better_supabase"."course_lesson_progress" ("user_id");

-- One per completed enrollment of a course that issues certificates. code is
-- the random value a verification link carries.
create table if not exists "better_supabase"."course_certificates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "course_id" uuid not null references "better_supabase"."courses" ("id") on delete cascade,
  "enrollment_id" uuid not null references "better_supabase"."enrollments" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "code" text not null unique check ("code" ~ '^[0-9a-f]{32}$'),
  "issued_at" timestamptz not null default now(),
  "revoked_at" timestamptz,
  constraint "course_certificates_enrollment_key" unique ("enrollment_id")
);
create index if not exists "course_certificates_parent_idx" on "better_supabase"."course_certificates" ("course_id");
create index if not exists "course_certificates_user_idx" on "better_supabase"."course_certificates" ("user_id");

alter table "better_supabase"."courses" enable row level security;
revoke all on "better_supabase"."courses" from public, anon, authenticated;
grant select on "better_supabase"."courses" to authenticated;
grant all on "better_supabase"."courses" to service_role;
drop policy if exists "courses_read" on "better_supabase"."courses";
create policy courses_read on "better_supabase"."courses"
  for select to authenticated
  using (("status" = 'published' and "tenant_id" in (select better_supabase.tenant_ids_with('courses.read'))) or "tenant_id" in (select better_supabase.tenant_ids_with('courses.manage')));
alter table "better_supabase"."course_modules" enable row level security;
revoke all on "better_supabase"."course_modules" from public, anon, authenticated;
grant select on "better_supabase"."course_modules" to authenticated;
grant all on "better_supabase"."course_modules" to service_role;
drop policy if exists "course_modules_read" on "better_supabase"."course_modules";
create policy course_modules_read on "better_supabase"."course_modules"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."courses" x where x."id" = "better_supabase"."course_modules"."course_id"));
alter table "better_supabase"."course_lessons" enable row level security;
revoke all on "better_supabase"."course_lessons" from public, anon, authenticated;
grant select on "better_supabase"."course_lessons" to authenticated;
grant all on "better_supabase"."course_lessons" to service_role;
drop policy if exists "course_lessons_read" on "better_supabase"."course_lessons";
create policy course_lessons_read on "better_supabase"."course_lessons"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('courses.manage')));
alter table "better_supabase"."course_lesson_progress" enable row level security;
revoke all on "better_supabase"."course_lesson_progress" from public, anon, authenticated;
grant select on "better_supabase"."course_lesson_progress" to authenticated;
grant all on "better_supabase"."course_lesson_progress" to service_role;
drop policy if exists "course_lesson_progress_read" on "better_supabase"."course_lesson_progress";
create policy course_lesson_progress_read on "better_supabase"."course_lesson_progress"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('courses.enroll')) or "tenant_id" in (select better_supabase.tenant_ids_with('courses.manage')));
alter table "better_supabase"."course_certificates" enable row level security;
revoke all on "better_supabase"."course_certificates" from public, anon, authenticated;
grant select on "better_supabase"."course_certificates" to authenticated;
grant all on "better_supabase"."course_certificates" to service_role;
drop policy if exists "course_certificates_read" on "better_supabase"."course_certificates";
create policy course_certificates_read on "better_supabase"."course_certificates"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('courses.enroll')) or "tenant_id" in (select better_supabase.tenant_ids_with('courses.manage')));

-- A course as JSON, with its extra columns under fields.
create or replace function "better_supabase"."course_json"(course_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'summary', x."summary", 'status', x."status", 'certificate', x."issues_certificate", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) from "better_supabase"."courses" x where x."id" = course_json.course_id
$$;
revoke execute on function "better_supabase"."course_json"(uuid) from public, anon, authenticated;

-- The course's required lessons in module rank, then lesson rank order: the
-- steps of its enrollment program.
create or replace function "better_supabase"."course_steps"(course_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(y."id"::text order by z."rank", z."id", y."rank", y."id"), '{}')
  from "better_supabase"."course_lessons" y join "better_supabase"."course_modules" z on z."id" = y."module_id"
  where y."course_id" = course_steps.course_id and y."required"
$$;
revoke execute on function "better_supabase"."course_steps"(uuid) from public, anon, authenticated;

-- After an enrollment's progress changed from status was: records
-- course.completed when it just completed, and issues the certificate when
-- the course gives one.
create or replace function "better_supabase"."course_finish"(enrollment_id uuid, was text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_enrollment record;
  v_certificate "better_supabase"."course_certificates";
begin
  select x."id" as id, x."tenant_id" as tenant, x."status" as status, x."user_id" as learner, y."id" as course, y."issues_certificate" as certifies
  into v_enrollment
  from "better_supabase"."enrollments" x join "better_supabase"."courses" y on ('course:' || y."id"::text) = x."program"
  where x."id" = course_finish.enrollment_id;
  if v_enrollment.id is null or v_enrollment.status <> 'completed' then
    return;
  end if;
  if course_finish.was is distinct from 'completed' then
    null;
  end if;
  if v_enrollment.certifies then
    insert into "better_supabase"."course_certificates" ("tenant_id", "course_id", "enrollment_id", "user_id", "code")
    values (v_enrollment.tenant, v_enrollment.course, v_enrollment.id, v_enrollment.learner, encode(extensions.gen_random_bytes(16), 'hex'))
    on conflict on constraint "course_certificates_enrollment_key" do nothing
    returning * into v_certificate;
    if v_certificate."id" is not null then
      null;
    end if;
  end if;
end;
$$;
revoke execute on function "better_supabase"."course_finish"(uuid, text) from public, anon, authenticated;

-- Gives every live enrollment in the course its current required lessons and
-- finishes the ones that complete with them.
create or replace function "better_supabase"."course_sync"(course_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_course "better_supabase"."courses";
  v_steps text[];
  v_row record;
begin
  select * into v_course from "better_supabase"."courses" x where x."id" = course_sync.course_id;
  if v_course."id" is null then
    return;
  end if;
  v_steps := "better_supabase"."course_steps"(v_course."id");
  for v_row in
    select x."id" as id, x."subject_id" as subject, x."status" as status from "better_supabase"."enrollments" x
    where x."tenant_id" = v_course."tenant_id" and x."program" = ('course:' || v_course."id"::text)
      and x."status" <> 'cancelled' and x."steps" is distinct from v_steps
  loop
    perform "better_supabase"."enrollment_ensure"(v_course."tenant_id", ('course:' || v_course."id"::text), null, v_steps, 'user', v_row.subject, auth.uid());
    perform "better_supabase"."course_finish"(v_row.id, v_row.status);
  end loop;
end;
$$;
revoke execute on function "better_supabase"."course_sync"(uuid) from public, anon, authenticated;

-- Creates or changes a course. course is { id?, key, title, summary, status,
-- certificate, fields }; keys left out keep their value.
create or replace function "better_supabase"."save_course"(tenant uuid, course jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."courses";
  v_row "better_supabase"."courses";
  v_key text;
  v_title text;
  v_summary text;
  v_status text;
  v_certificate boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_course.tenant is not null and coalesce(better_supabase.can('tenant', save_course.tenant, 'courses.manage'), false))) then
    raise exception 'not allowed to manage courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  if save_course.course is null or jsonb_typeof(save_course.course) <> 'object' then
    raise exception 'course must be an object' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  v_id := nullif(save_course.course ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."courses" x where x."id" = v_id and x."tenant_id" = save_course.tenant for update;
    if v_old."id" is null then
      raise exception 'course not found' using errcode = 'P0002', hint = 'COURSE_NOT_FOUND';
    end if;
  end if;
  v_key := coalesce(save_course.course ->> 'key', v_old."key");
  v_title := trim(coalesce(save_course.course ->> 'title', v_old."title"));
  v_summary := case when save_course.course ? 'summary' then nullif(trim(save_course.course ->> 'summary'), '') else v_old."summary" end;
  v_status := coalesce(save_course.course ->> 'status', v_old."status", 'draft');
  v_certificate := case when save_course.course ? 'certificate' then (save_course.course ->> 'certificate')::boolean else coalesce(v_old."issues_certificate", true) end;
  if v_key is null or v_key !~ '^[a-z][a-z0-9-]{0,62}$' then
    raise exception 'key: use lowercase letters, digits or "-", starting with a letter' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_title is null or length(v_title) not between 1 and 200 then
    raise exception 'title must be 1 to 200 characters' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if length(v_summary) > 2000 then
    raise exception 'summary must be at most 2000 characters' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_status not in ('draft', 'published', 'archived') then
    raise exception 'status must be draft, published or archived' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."courses" ("tenant_id", "key", "title", "summary", "status", "issues_certificate", "created_by")
    values (save_course.tenant, v_key, v_title, v_summary, v_status, v_certificate, auth.uid())
    on conflict ("tenant_id", "key") do nothing
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'a course with this key already exists' using errcode = '23505', hint = 'COURSE_EXISTS';
    end if;
  else
    begin
      update "better_supabase"."courses" x
      set "key" = v_key, "title" = v_title, "summary" = v_summary, "status" = v_status,
        "issues_certificate" = v_certificate, "updated_at" = now()
      where x."id" = v_old."id"
      returning * into v_row;
    exception when unique_violation then
      raise exception 'a course with this key already exists' using errcode = '23505', hint = 'COURSE_EXISTS';
    end;
  end if;
  update "better_supabase"."courses" x set "app_note" = case when (save_course.course -> 'fields') ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."courses", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each((save_course.course -> 'fields')) e where e.key in ('app_note'))) r
  where x."id" = v_row."id"
  returning x.* into v_row;
  null;
  return "better_supabase"."course_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."save_course"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_course"(uuid, jsonb) to authenticated, service_role;

-- Deletes a course with its modules, lessons, enrollments, progress and
-- certificates; false when it was already gone.
create or replace function "better_supabase"."delete_course"(course_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."courses";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."courses" x where x."id" = delete_course.course_id for update;
  if v_row."id" is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'courses.manage'), false))) then
    raise exception 'not allowed to manage courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  delete from "better_supabase"."enrollments" x where x."tenant_id" = v_row."tenant_id" and x."program" = ('course:' || v_row."id"::text);
  delete from "better_supabase"."courses" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_course"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_course"(uuid) to authenticated, service_role;

-- The organization's courses by title. Without courses.manage only the
-- published ones.
create or replace function "better_supabase"."list_courses"(tenant uuid, status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_manage boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_courses.tenant is not null and coalesce(better_supabase.can('tenant', list_courses.tenant, 'courses.manage'), false)));
begin
  if not (v_manage or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_courses.tenant is not null and coalesce(better_supabase.can('tenant', list_courses.tenant, 'courses.read'), false)))) then
    raise exception 'not allowed to read courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  if list_courses.status is not null and list_courses.status not in ('draft', 'published', 'archived') then
    raise exception 'status must be draft, published or archived' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  return coalesce((
    select jsonb_agg((jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'summary', x."summary", 'status', x."status", 'certificate', x."issues_certificate", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) order by x."title", x."id")
    from "better_supabase"."courses" x
    where x."tenant_id" = list_courses.tenant
      and (v_manage or x."status" = 'published')
      and (list_courses.status is null or x."status" = list_courses.status)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_courses"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_courses"(uuid, text) to authenticated, service_role;

-- Creates or changes a module of a course. module is { id?, title, rank? };
-- a new module without a rank goes last.
create or replace function "better_supabase"."save_course_module"(course_id uuid, module jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_course "better_supabase"."courses";
  v_old "better_supabase"."course_modules";
  v_row "better_supabase"."course_modules";
  v_id uuid;
  v_title text;
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_course from "better_supabase"."courses" x where x."id" = save_course_module.course_id;
  if v_course."id" is null then
    raise exception 'course not found' using errcode = 'P0002', hint = 'COURSE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.manage'), false))) then
    raise exception 'not allowed to manage courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  if save_course_module.module is null or jsonb_typeof(save_course_module.module) <> 'object' then
    raise exception 'module must be an object' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  v_id := nullif(save_course_module.module ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."course_modules" x where x."id" = v_id and x."course_id" = v_course."id" for update;
    if v_old."id" is null then
      raise exception 'course module not found' using errcode = 'P0002', hint = 'COURSE_MODULE_NOT_FOUND';
    end if;
  end if;
  v_title := trim(coalesce(save_course_module.module ->> 'title', v_old."title"));
  if v_title is null or length(v_title) not between 1 and 200 then
    raise exception 'title must be 1 to 200 characters' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  select max(x."rank") into v_last from "better_supabase"."course_modules" x where x."course_id" = v_course."id";
  v_rank := coalesce(nullif(save_course_module.module ->> 'rank', ''), coalesce(v_old."rank", case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end));
  if v_rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a rank key' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."course_modules" ("tenant_id", "course_id", "title", "rank")
    values (v_course."tenant_id", v_course."id", v_title, v_rank)
    returning * into v_row;
  else
    update "better_supabase"."course_modules" x set "title" = v_title, "rank" = v_rank, "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  update "better_supabase"."courses" x set "updated_at" = now() where x."id" = v_course."id";
  perform "better_supabase"."course_sync"(v_course."id");
  return jsonb_build_object('id', v_row."id", 'courseId', v_row."course_id", 'title', v_row."title", 'rank', v_row."rank", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_course_module"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_course_module"(uuid, jsonb) to authenticated, service_role;

-- Deletes a module with its lessons; false when it was already gone.
create or replace function "better_supabase"."delete_course_module"(module_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."course_modules";
  v_course "better_supabase"."courses";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."course_modules" x where x."id" = delete_course_module.module_id for update;
  if v_row."id" is null then
    return false;
  end if;
  select * into v_course from "better_supabase"."courses" x where x."id" = v_row."course_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.manage'), false))) then
    raise exception 'not allowed to manage courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  delete from "better_supabase"."course_modules" x where x."id" = v_row."id";
  perform "better_supabase"."course_sync"(v_course."id");
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_course_module"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_course_module"(uuid) to authenticated, service_role;

-- Creates or changes a lesson. lesson is { id?, moduleId, title, kind, body,
-- mediaUrl, formId, required, minutes, rank? }; keys left out keep their
-- value, and a lesson without a rank goes last in its module. A quiz lesson
-- names the form that grades it.
create or replace function "better_supabase"."save_course_lesson"(course_id uuid, lesson jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_course "better_supabase"."courses";
  v_old "better_supabase"."course_lessons";
  v_row "better_supabase"."course_lessons";
  v_new record;
  v_id uuid;
  v_last text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_course from "better_supabase"."courses" x where x."id" = save_course_lesson.course_id;
  if v_course."id" is null then
    raise exception 'course not found' using errcode = 'P0002', hint = 'COURSE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.manage'), false))) then
    raise exception 'not allowed to manage courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  if save_course_lesson.lesson is null or jsonb_typeof(save_course_lesson.lesson) <> 'object' then
    raise exception 'lesson must be an object' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  v_id := nullif(save_course_lesson.lesson ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."course_lessons" x where x."id" = v_id and x."course_id" = v_course."id" for update;
    if v_old."id" is null then
      raise exception 'course lesson not found' using errcode = 'P0002', hint = 'COURSE_LESSON_NOT_FOUND';
    end if;
  end if;
  select
    v_course."tenant_id" as tenant,
    coalesce(nullif(save_course_lesson.lesson ->> 'moduleId', '')::uuid, v_old."module_id") as module,
    trim(coalesce(save_course_lesson.lesson ->> 'title', v_old."title")) as title,
    coalesce(save_course_lesson.lesson ->> 'kind', v_old."kind", 'content') as kind,
    case when save_course_lesson.lesson ? 'body' then nullif(save_course_lesson.lesson -> 'body', 'null'::jsonb) else v_old."body" end as body,
    case when save_course_lesson.lesson ? 'mediaUrl' then nullif(save_course_lesson.lesson ->> 'mediaUrl', '') else v_old."media_url" end as media,
    case when save_course_lesson.lesson ? 'formId' then nullif(save_course_lesson.lesson ->> 'formId', '')::uuid else v_old."form_id" end as form,
    case when save_course_lesson.lesson ? 'required' then (save_course_lesson.lesson ->> 'required')::boolean else coalesce(v_old."required", true) end as required,
    case when save_course_lesson.lesson ? 'minutes' then (save_course_lesson.lesson ->> 'minutes')::integer else v_old."duration_minutes" end as minutes
  into v_new;
  if v_new.module is null or not exists (select 1 from "better_supabase"."course_modules" x where x."id" = v_new.module and x."course_id" = v_course."id") then
    raise exception 'moduleId: pass a module of this course' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_new.title is null or length(v_new.title) not between 1 and 200 then
    raise exception 'title must be 1 to 200 characters' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_new.kind not in ('content', 'video', 'quiz') then
    raise exception 'kind must be content, video or quiz' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if (v_new.kind = 'quiz') <> (v_new.form is not null) then
    raise exception 'a quiz lesson needs a formId, and only a quiz lesson takes one' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_new.form is not null then
    raise exception 'quiz lessons need the forms block' using errcode = '55000', hint = 'COURSE_QUIZ_UNAVAILABLE';
  end if;
  if v_new.body is not null and octet_length(v_new.body::text) > 1000000 then
    raise exception 'body must be at most 1 MB' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_new.media is not null and (v_new.media !~ '^https?://' or length(v_new.media) > 2000) then
    raise exception 'mediaUrl must be an http or https URL of at most 2000 characters' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_new.minutes is not null and v_new.minutes not between 1 and 10000 then
    raise exception 'minutes must be from 1 to 10000' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  select max(x."rank") into v_last from "better_supabase"."course_lessons" x where x."module_id" = v_new.module and x."id" is distinct from v_old."id";
  v_last := coalesce(nullif(save_course_lesson.lesson ->> 'rank', ''), case when v_old."module_id" = v_new.module then v_old."rank" else case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end end);
  if v_last !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a rank key' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."course_lessons" ("tenant_id", "course_id", "module_id", "title", "kind", "body", "media_url", "form_id", "required", "duration_minutes", "rank")
    values (v_new.tenant, v_course."id", v_new.module, v_new.title, v_new.kind, v_new.body, v_new.media, v_new.form, v_new.required, v_new.minutes, v_last)
    returning * into v_row;
  else
    update "better_supabase"."course_lessons" x
    set "module_id" = v_new.module, "title" = v_new.title, "kind" = v_new.kind, "body" = v_new.body, "media_url" = v_new.media, "form_id" = v_new.form, "required" = v_new.required, "duration_minutes" = v_new.minutes,
      "rank" = v_last, "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  update "better_supabase"."courses" x set "updated_at" = now() where x."id" = v_course."id";
  perform "better_supabase"."course_sync"(v_course."id");
  return jsonb_build_object('id', v_row."id", 'courseId', v_row."course_id", 'moduleId', v_row."module_id", 'title', v_row."title", 'kind', v_row."kind", 'body', v_row."body", 'mediaUrl', v_row."media_url", 'formId', v_row."form_id", 'required', v_row."required", 'minutes', v_row."duration_minutes", 'rank', v_row."rank", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_course_lesson"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_course_lesson"(uuid, jsonb) to authenticated, service_role;

-- Deletes a lesson with its progress; false when it was already gone.
create or replace function "better_supabase"."delete_course_lesson"(lesson_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."course_lessons";
  v_course "better_supabase"."courses";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."course_lessons" x where x."id" = delete_course_lesson.lesson_id for update;
  if v_row."id" is null then
    return false;
  end if;
  select * into v_course from "better_supabase"."courses" x where x."id" = v_row."course_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.manage'), false))) then
    raise exception 'not allowed to manage courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  delete from "better_supabase"."course_lessons" x where x."id" = v_row."id";
  perform "better_supabase"."course_sync"(v_course."id");
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_course_lesson"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_course_lesson"(uuid) to authenticated, service_role;

-- Revokes a certificate; false when it already was.
create or replace function "better_supabase"."revoke_course_certificate"(certificate_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."course_certificates";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."course_certificates" x where x."id" = revoke_course_certificate.certificate_id for update;
  if v_row."id" is null then
    raise exception 'course certificate not found' using errcode = 'P0002', hint = 'COURSE_CERTIFICATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'courses.manage'), false))) then
    raise exception 'not allowed to manage courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  if v_row."revoked_at" is not null then
    return false;
  end if;
  update "better_supabase"."course_certificates" x set "revoked_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_course_certificate"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_course_certificate"(uuid) to authenticated, service_role;

-- A learner's progress in a course: the enrollment's counts, an entry per
-- lesson they started and their certificate.
create or replace function "better_supabase"."course_learner_json"(enrollment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'enrollmentId', x."id", 'courseId', substr(x."program", 8)::uuid, 'organizationId', x."tenant_id", 'userId', x."user_id",
    'status', x."status", 'completedLessons', x."completed_steps", 'totalLessons', cardinality(x."steps"),
    'enrolledAt', x."enrolled_at", 'completedAt', x."completed_at", 'cancelledAt', x."cancelled_at", 'updatedAt', x."updated_at",
    'lessons', coalesce((
      select jsonb_agg(jsonb_build_object('lessonId', y."lesson_id", 'startedAt', y."started_at", 'completedAt', y."completed_at", 'attempts', y."attempts", 'submissionId', y."submission_id", 'score', y."score", 'maxScore', y."max_score", 'passed', y."passed") order by y."started_at", y."lesson_id")
      from "better_supabase"."course_lesson_progress" y where y."enrollment_id" = x."id"
    ), '[]'::jsonb),
    'certificate', (select jsonb_build_object('id', z."id", 'courseId', z."course_id", 'userId', z."user_id", 'code', z."code", 'issuedAt', z."issued_at", 'revokedAt', z."revoked_at") from "better_supabase"."course_certificates" z where z."enrollment_id" = x."id")
  )
  from "better_supabase"."enrollments" x
  where x."id" = course_learner_json.enrollment_id
$$;
revoke execute on function "better_supabase"."course_learner_json"(uuid) from public, anon, authenticated;

-- Marks lesson done in the enrollment after its progress entry completed:
-- the step when the lesson is required, course_lesson.completed when it just
-- completed (fresh), then course_finish.
create or replace function "better_supabase"."course_lesson_done"(enrollment_id uuid, lesson_id uuid, fresh boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."enrollments";
  v_lesson "better_supabase"."course_lessons";
  v_was text;
begin
  select * into v_row from "better_supabase"."enrollments" x where x."id" = course_lesson_done.enrollment_id;
  select * into v_lesson from "better_supabase"."course_lessons" x where x."id" = course_lesson_done.lesson_id;
  perform "better_supabase"."enrollment_ensure"(v_row."tenant_id", v_row."program", null, "better_supabase"."course_steps"(v_lesson."course_id"), 'user', v_row."subject_id", auth.uid());
  select x."status" into v_was from "better_supabase"."enrollments" x where x."id" = v_row."id";
  if v_lesson."required" then
    perform "better_supabase"."enrollment_mark"(v_row."id", v_lesson."id"::text, true, auth.uid());
  end if;
  if course_lesson_done.fresh then
    null;
  end if;
  perform "better_supabase"."course_finish"(v_row."id", v_was);
end;
$$;
revoke execute on function "better_supabase"."course_lesson_done"(uuid, uuid, boolean) from public, anon, authenticated;

-- A course with its modules and their lessons in rank order, without lesson
-- content, and the caller's progress in it (null when not enrolled).
create or replace function "better_supabase"."course_outline"(course_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_course "better_supabase"."courses";
  v_row "better_supabase"."enrollments";
begin
  select * into v_course from "better_supabase"."courses" x where x."id" = course_outline.course_id;
  if v_course."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.manage'), false)))
    or (v_course."status" = 'published' and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.read'), false))))
    or exists (select 1 from "better_supabase"."enrollments" y where y."tenant_id" = v_course."tenant_id" and y."program" = ('course:' || v_course."id"::text)
      and y."subject_type" = 'user' and y."subject_id" = auth.uid()::text and y."status" <> 'cancelled')) then
    raise exception 'course not found' using errcode = 'P0002', hint = 'COURSE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = v_course."tenant_id" and x."program" = ('course:' || v_course."id"::text)
    and x."subject_type" = 'user' and x."subject_id" = auth.uid()::text;
  return (jsonb_build_object('id', v_course."id", 'organizationId', v_course."tenant_id", 'key', v_course."key", 'title', v_course."title", 'summary', v_course."summary", 'status', v_course."status", 'certificate', v_course."issues_certificate", 'createdBy', v_course."created_by", 'createdAt', v_course."created_at", 'updatedAt', v_course."updated_at") || jsonb_build_object('fields', jsonb_build_object('app_note', v_course."app_note"))) || jsonb_build_object(
    'modules', coalesce((
      select jsonb_agg(jsonb_build_object('id', z."id", 'title', z."title", 'rank', z."rank", 'lessons', coalesce((
        select jsonb_agg(jsonb_build_object('id', y."id", 'moduleId', y."module_id", 'title', y."title", 'kind', y."kind", 'required', y."required",
          'minutes', y."duration_minutes", 'rank', y."rank", 'completedAt', (
            select w."completed_at" from "better_supabase"."course_lesson_progress" w where w."enrollment_id" = v_row."id" and w."lesson_id" = y."id"
          )) order by y."rank", y."id")
        from "better_supabase"."course_lessons" y where y."module_id" = z."id"
      ), '[]'::jsonb)) order by z."rank", z."id")
      from "better_supabase"."course_modules" z where z."course_id" = v_course."id"
    ), '[]'::jsonb),
    'progress', case when v_row."id" is null then null else "better_supabase"."course_learner_json"(v_row."id") end
  );
end;
$$;
revoke execute on function "better_supabase"."course_outline"(uuid) from public, anon;
grant execute on function "better_supabase"."course_outline"(uuid) to authenticated, service_role;

-- A lesson with its content and quiz for the course's managers and its
-- enrolled learners, with the caller's progress entry.
create or replace function "better_supabase"."course_lesson"(lesson_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lesson "better_supabase"."course_lessons";
  v_course "better_supabase"."courses";
  v_row "better_supabase"."enrollments";
  v_entry "better_supabase"."course_lesson_progress";
begin
  select * into v_lesson from "better_supabase"."course_lessons" x where x."id" = course_lesson.lesson_id;
  if v_lesson."id" is null then
    raise exception 'course lesson not found' using errcode = 'P0002', hint = 'COURSE_LESSON_NOT_FOUND';
  end if;
  select * into v_course from "better_supabase"."courses" x where x."id" = v_lesson."course_id";
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = v_course."tenant_id" and x."program" = ('course:' || v_course."id"::text)
    and x."subject_type" = 'user' and x."subject_id" = auth.uid()::text and x."status" <> 'cancelled';
  if v_row."id" is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.manage'), false))) then
    if ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.manage'), false)))
    or (v_course."status" = 'published' and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.read'), false))))
    or exists (select 1 from "better_supabase"."enrollments" y where y."tenant_id" = v_course."tenant_id" and y."program" = ('course:' || v_course."id"::text)
      and y."subject_type" = 'user' and y."subject_id" = auth.uid()::text and y."status" <> 'cancelled')) then
      raise exception 'you are not enrolled in this course' using errcode = 'P0002', hint = 'COURSE_NOT_ENROLLED';
    end if;
    raise exception 'course lesson not found' using errcode = 'P0002', hint = 'COURSE_LESSON_NOT_FOUND';
  end if;
  select * into v_entry from "better_supabase"."course_lesson_progress" x where x."enrollment_id" = v_row."id" and x."lesson_id" = v_lesson."id";
  return jsonb_build_object('id', v_lesson."id", 'courseId', v_lesson."course_id", 'moduleId', v_lesson."module_id", 'title', v_lesson."title",
    'kind', v_lesson."kind", 'body', v_lesson."body", 'mediaUrl', v_lesson."media_url", 'formId', v_lesson."form_id",
    'required', v_lesson."required", 'minutes', v_lesson."duration_minutes", 'rank', v_lesson."rank",
    'createdAt', v_lesson."created_at", 'updatedAt', v_lesson."updated_at",
    'quiz', case when v_lesson."form_id" is null then null else null::jsonb end,
    'progress', case when v_entry."lesson_id" is null then null else jsonb_build_object('lessonId', v_entry."lesson_id", 'startedAt', v_entry."started_at", 'completedAt', v_entry."completed_at", 'attempts', v_entry."attempts", 'submissionId', v_entry."submission_id", 'score', v_entry."score", 'maxScore', v_entry."max_score", 'passed', v_entry."passed") end);
end;
$$;
revoke execute on function "better_supabase"."course_lesson"(uuid) from public, anon;
grant execute on function "better_supabase"."course_lesson"(uuid) to authenticated, service_role;

-- Enrolls a user in a published course: the caller with courses.read, or
-- another user with courses.enroll. Enrolling again returns the enrollment;
-- enrolling a cancelled one starts it again with its completed lessons.
create or replace function "better_supabase"."enroll_in_course"(course_id uuid, user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_course "better_supabase"."courses";
  v_row "better_supabase"."enrollments";
  v_user uuid := coalesce(enroll_in_course.user_id, auth.uid());
  v_enrollment record;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_course from "better_supabase"."courses" x where x."id" = enroll_in_course.course_id;
  if v_course."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.manage'), false)))
    or (v_course."status" = 'published' and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.read'), false))))
    or exists (select 1 from "better_supabase"."enrollments" y where y."tenant_id" = v_course."tenant_id" and y."program" = ('course:' || v_course."id"::text)
      and y."subject_type" = 'user' and y."subject_id" = auth.uid()::text and y."status" <> 'cancelled')) then
    raise exception 'course not found' using errcode = 'P0002', hint = 'COURSE_NOT_FOUND';
  end if;
  if v_user is null then
    raise exception 'sign in to enroll' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  if v_user is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.enroll'), false))) then
    raise exception 'not allowed to enroll others in courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  if v_user = auth.uid() and not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.enroll'), false)))) then
    raise exception 'not allowed to enroll in courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  if v_course."status" <> 'published' then
    raise exception 'only a published course takes enrollments' using errcode = '55000', hint = 'COURSE_NOT_PUBLISHED';
  end if;
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = v_course."tenant_id" and x."program" = ('course:' || v_course."id"::text)
    and x."subject_type" = 'user' and x."subject_id" = v_user::text
  for update;
  if v_row."id" is not null and v_row."status" <> 'cancelled' then
    return "better_supabase"."course_learner_json"(v_row."id");
  end if;
  if v_row."id" is not null then
    -- Clearing the steps makes enrollment_ensure take the current ones and
    -- recount the lessons completed before.
    update "better_supabase"."enrollments" x
    set "status" = 'active', "cancelled_at" = null, "enrolled_by" = auth.uid(), "enrolled_at" = now(), "steps" = '{}'
    where x."id" = v_row."id";
  end if;
  v_id := "better_supabase"."enrollment_ensure"(v_course."tenant_id", ('course:' || v_course."id"::text), null, "better_supabase"."course_steps"(v_course."id"), 'user', v_user::text, auth.uid());
  select * into v_row from "better_supabase"."enrollments" x where x."id" = v_id;
  select v_row."id" as id, v_row."tenant_id" as tenant, v_course."id" as course, v_row."user_id" as learner into v_enrollment;
  null;
  perform "better_supabase"."course_finish"(v_id, 'active');
  return "better_supabase"."course_learner_json"(v_id);
end;
$$;
revoke execute on function "better_supabase"."enroll_in_course"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."enroll_in_course"(uuid, uuid) to authenticated, service_role;

-- Cancels a user's active enrollment in a course: the caller's own, or
-- another user's with courses.enroll. Their progress stays.
create or replace function "better_supabase"."unenroll_from_course"(course_id uuid, user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_course "better_supabase"."courses";
  v_row "better_supabase"."enrollments";
  v_user uuid := coalesce(unenroll_from_course.user_id, auth.uid());
  v_enrollment record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_course from "better_supabase"."courses" x where x."id" = unenroll_from_course.course_id;
  if v_course."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.manage'), false)))
    or (v_course."status" = 'published' and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.read'), false))))
    or exists (select 1 from "better_supabase"."enrollments" y where y."tenant_id" = v_course."tenant_id" and y."program" = ('course:' || v_course."id"::text)
      and y."subject_type" = 'user' and y."subject_id" = auth.uid()::text and y."status" <> 'cancelled')) then
    raise exception 'course not found' using errcode = 'P0002', hint = 'COURSE_NOT_FOUND';
  end if;
  if v_user is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.enroll'), false))) then
    raise exception 'not allowed to unenroll others from courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = v_course."tenant_id" and x."program" = ('course:' || v_course."id"::text)
    and x."subject_type" = 'user' and x."subject_id" = v_user::text
  for update;
  if v_row."id" is null then
    raise exception 'this user is not enrolled in this course' using errcode = 'P0002', hint = 'COURSE_NOT_ENROLLED';
  end if;
  if v_row."status" = 'completed' then
    raise exception 'a completed enrollment can''t be cancelled' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_row."status" = 'active' then
    update "better_supabase"."enrollments" x
    set "status" = 'cancelled', "cancelled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    select v_row."id" as id, v_row."tenant_id" as tenant, v_course."id" as course, v_row."user_id" as learner into v_enrollment;
    null;
  end if;
  return "better_supabase"."course_learner_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."unenroll_from_course"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."unenroll_from_course"(uuid, uuid) to authenticated, service_role;

-- Records that the enrolled caller opened a lesson; returns its progress
-- entry.
create or replace function "better_supabase"."start_course_lesson"(lesson_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_lesson "better_supabase"."course_lessons";
  v_row "better_supabase"."enrollments";
  v_entry "better_supabase"."course_lesson_progress";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_lesson from "better_supabase"."course_lessons" x where x."id" = start_course_lesson.lesson_id;
  if v_lesson."id" is null then
    raise exception 'course lesson not found' using errcode = 'P0002', hint = 'COURSE_LESSON_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = v_lesson."tenant_id" and x."program" = ('course:' || v_lesson."course_id"::text)
    and x."subject_type" = 'user' and x."subject_id" = auth.uid()::text and x."status" <> 'cancelled';
  if v_row."id" is null then
    raise exception 'you are not enrolled in this course' using errcode = 'P0002', hint = 'COURSE_NOT_ENROLLED';
  end if;
  insert into "better_supabase"."course_lesson_progress" ("enrollment_id", "lesson_id", "tenant_id", "course_id", "user_id")
  values (v_row."id", v_lesson."id", v_lesson."tenant_id", v_lesson."course_id", auth.uid())
  on conflict do nothing;
  select * into v_entry from "better_supabase"."course_lesson_progress" x where x."enrollment_id" = v_row."id" and x."lesson_id" = v_lesson."id";
  return jsonb_build_object('lessonId', v_entry."lesson_id", 'startedAt', v_entry."started_at", 'completedAt', v_entry."completed_at", 'attempts', v_entry."attempts", 'submissionId', v_entry."submission_id", 'score', v_entry."score", 'maxScore', v_entry."max_score", 'passed', v_entry."passed");
end;
$$;
revoke execute on function "better_supabase"."start_course_lesson"(uuid) from public, anon;
grant execute on function "better_supabase"."start_course_lesson"(uuid) to authenticated, service_role;

-- Marks a content or video lesson done, or not done, for the enrolled
-- caller; returns their progress. A quiz lesson completes by passing it.
create or replace function "better_supabase"."complete_course_lesson"(lesson_id uuid, done boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_lesson "better_supabase"."course_lessons";
  v_row "better_supabase"."enrollments";
  v_before timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_lesson from "better_supabase"."course_lessons" x where x."id" = complete_course_lesson.lesson_id;
  if v_lesson."id" is null then
    raise exception 'course lesson not found' using errcode = 'P0002', hint = 'COURSE_LESSON_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = v_lesson."tenant_id" and x."program" = ('course:' || v_lesson."course_id"::text)
    and x."subject_type" = 'user' and x."subject_id" = auth.uid()::text and x."status" <> 'cancelled'
  for update;
  if v_row."id" is null then
    raise exception 'you are not enrolled in this course' using errcode = 'P0002', hint = 'COURSE_NOT_ENROLLED';
  end if;
  if v_lesson."kind" = 'quiz' then
    raise exception 'a quiz lesson completes when you pass its quiz' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  select x."completed_at" into v_before from "better_supabase"."course_lesson_progress" x
  where x."enrollment_id" = v_row."id" and x."lesson_id" = v_lesson."id";
  if complete_course_lesson.done then
    insert into "better_supabase"."course_lesson_progress" ("enrollment_id", "lesson_id", "tenant_id", "course_id", "user_id", "completed_at")
    values (v_row."id", v_lesson."id", v_lesson."tenant_id", v_lesson."course_id", auth.uid(), now())
    on conflict on constraint "course_lesson_progress_pkey" do update
    set "completed_at" = coalesce("better_supabase"."course_lesson_progress"."completed_at", now()), "updated_at" = now();
    perform "better_supabase"."course_lesson_done"(v_row."id", v_lesson."id", v_before is null);
  else
    update "better_supabase"."course_lesson_progress" x set "completed_at" = null, "updated_at" = now()
    where x."enrollment_id" = v_row."id" and x."lesson_id" = v_lesson."id";
    if v_lesson."required" then
      perform "better_supabase"."enrollment_ensure"(v_row."tenant_id", v_row."program", null, "better_supabase"."course_steps"(v_lesson."course_id"), 'user', v_row."subject_id", auth.uid());
      perform "better_supabase"."enrollment_mark"(v_row."id", v_lesson."id"::text, false, auth.uid());
    end if;
  end if;
  return "better_supabase"."course_learner_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."complete_course_lesson"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."complete_course_lesson"(uuid, boolean) to authenticated, service_role;

-- A user's progress in a course, or null when not enrolled: the caller's
-- own, or another user's with courses.enroll or courses.manage.
create or replace function "better_supabase"."course_progress"(course_id uuid, user_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_course "better_supabase"."courses";
  v_row "better_supabase"."enrollments";
  v_user uuid := coalesce(course_progress.user_id, auth.uid());
begin
  select * into v_course from "better_supabase"."courses" x where x."id" = course_progress.course_id;
  if v_course."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.manage'), false)))
    or (v_course."status" = 'published' and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.read'), false))))
    or exists (select 1 from "better_supabase"."enrollments" y where y."tenant_id" = v_course."tenant_id" and y."program" = ('course:' || v_course."id"::text)
      and y."subject_type" = 'user' and y."subject_id" = auth.uid()::text and y."status" <> 'cancelled')) then
    raise exception 'course not found' using errcode = 'P0002', hint = 'COURSE_NOT_FOUND';
  end if;
  if v_user is distinct from auth.uid() and not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.enroll'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.manage'), false)))) then
    raise exception 'not allowed to read other learners'' progress' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = v_course."tenant_id" and x."program" = ('course:' || v_course."id"::text)
    and x."subject_type" = 'user' and x."subject_id" = v_user::text;
  return case when v_row."id" is null then null else "better_supabase"."course_learner_json"(v_row."id") end;
end;
$$;
revoke execute on function "better_supabase"."course_progress"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."course_progress"(uuid, uuid) to authenticated, service_role;

-- The course's learners, most recently changed first: courses.enroll or
-- courses.manage.
create or replace function "better_supabase"."list_course_learners"(course_id uuid, status text default null, page_size integer default null, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_course "better_supabase"."courses";
begin
  select * into v_course from "better_supabase"."courses" x where x."id" = list_course_learners.course_id;
  if v_course."id" is null then
    raise exception 'course not found' using errcode = 'P0002', hint = 'COURSE_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.enroll'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.manage'), false)))) then
    raise exception 'not allowed to read the course''s learners' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  if list_course_learners.status is not null and list_course_learners.status not in ('active', 'completed', 'cancelled') then
    raise exception 'status must be active, completed or cancelled' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  return coalesce((
    select jsonb_agg("better_supabase"."course_learner_json"(y."id") order by y."updated_at" desc, y."id")
    from (
      select x."id", x."updated_at" from "better_supabase"."enrollments" x
      where x."tenant_id" = v_course."tenant_id" and x."program" = ('course:' || v_course."id"::text)
        and (list_course_learners.status is null or x."status" = list_course_learners.status)
        and (list_course_learners.before is null or x."updated_at" < list_course_learners.before)
      order by x."updated_at" desc, x."id"
      limit least(greatest(coalesce(list_course_learners.page_size, 50), 1), 200)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_course_learners"(uuid, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_course_learners"(uuid, text, integer, timestamptz) to authenticated, service_role;

-- Checks a certificate by the code its link carries. Anyone with the code
-- learns the course, when it was issued and whether it was revoked; null for
-- an unknown code.
create or replace function "better_supabase"."verify_course_certificate"(code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', z."id", 'courseId', z."course_id", 'courseTitle', y."title", 'organizationId', z."tenant_id",
    'issuedAt', z."issued_at", 'revokedAt', z."revoked_at", 'valid', z."revoked_at" is null)
  from "better_supabase"."course_certificates" z join "better_supabase"."courses" y on y."id" = z."course_id"
  where z."code" = lower(verify_course_certificate.code)
$$;
revoke execute on function "better_supabase"."verify_course_certificate"(text) from public;
grant execute on function "better_supabase"."verify_course_certificate"(text) to anon, authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."courses";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."courses";
create policy bsb_tenant_scope_select on "better_supabase"."courses" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("status" = 'published' and "tenant_id" in (select better_supabase.tenant_ids_with('courses.read'))) or "tenant_id" in (select better_supabase.tenant_ids_with('courses.manage')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."courses";
create policy bsb_tenant_scope_insert on "better_supabase"."courses" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."courses";
create policy bsb_tenant_scope_update on "better_supabase"."courses" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."courses";
create policy bsb_tenant_scope_delete on "better_supabase"."courses" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."course_modules";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."course_modules";
create policy bsb_tenant_scope_select on "better_supabase"."course_modules" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."courses" x where x."id" = "better_supabase"."course_modules"."course_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."course_modules";
create policy bsb_tenant_scope_insert on "better_supabase"."course_modules" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."course_modules";
create policy bsb_tenant_scope_update on "better_supabase"."course_modules" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."course_modules";
create policy bsb_tenant_scope_delete on "better_supabase"."course_modules" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."course_lessons";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."course_lessons";
create policy bsb_tenant_scope_select on "better_supabase"."course_lessons" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('courses.manage')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."course_lessons";
create policy bsb_tenant_scope_insert on "better_supabase"."course_lessons" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."course_lessons";
create policy bsb_tenant_scope_update on "better_supabase"."course_lessons" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."course_lessons";
create policy bsb_tenant_scope_delete on "better_supabase"."course_lessons" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."course_lesson_progress";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."course_lesson_progress";
create policy bsb_tenant_scope_select on "better_supabase"."course_lesson_progress" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('courses.enroll')) or "tenant_id" in (select better_supabase.tenant_ids_with('courses.manage')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."course_lesson_progress";
create policy bsb_tenant_scope_insert on "better_supabase"."course_lesson_progress" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."course_lesson_progress";
create policy bsb_tenant_scope_update on "better_supabase"."course_lesson_progress" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."course_lesson_progress";
create policy bsb_tenant_scope_delete on "better_supabase"."course_lesson_progress" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."course_certificates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."course_certificates";
create policy bsb_tenant_scope_select on "better_supabase"."course_certificates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('courses.enroll')) or "tenant_id" in (select better_supabase.tenant_ids_with('courses.manage')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."course_certificates";
create policy bsb_tenant_scope_insert on "better_supabase"."course_certificates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."course_certificates";
create policy bsb_tenant_scope_update on "better_supabase"."course_certificates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."course_certificates";
create policy bsb_tenant_scope_delete on "better_supabase"."course_certificates" as restrictive
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

-- ==== data supabase/better-supabase-data/900_better_supabase_128_courses.sql
-- better-supabase module: courses
-- @bsb-block-data courses
-- @bsb-hash sha256:be2ff5b96a994fd2b818c43f00e4213d79617735d6840d20eaac3479c0b564b5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('courses', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
