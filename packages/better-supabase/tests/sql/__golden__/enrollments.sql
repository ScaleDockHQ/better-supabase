-- ==== alone: schema supabase/schemas/900_better_supabase_036_enrollments.sql
-- better-supabase module: enrollments
-- @bsb-block enrollments@1 managed
-- @bsb-hash sha256:69e220c3637b0452a6e975d4caeef7408bdf8d0e5322af6bd189f2087bffda1e
-- Programs of steps per organization, and enrollments of a party, a member or any subject in them with step progress and completion. Onboarding checklists run on it.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_programs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_steps";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."enrollment_programs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  -- The subject types it enrolls; empty enrolls any.
  "subject_types" text[] not null default '{}',
  -- [{ id, title, description }], in order.
  "steps" jsonb not null default '[]'::jsonb check (jsonb_typeof("steps") = 'array'),
  "enabled" boolean not null default true,
  "version" integer not null default 1,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);

-- One per program and subject. A user's own onboarding checklist has no
-- tenant; user_id is set for user subjects so the row goes with the user.
create table if not exists "better_supabase"."enrollments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "program" text not null check (length("program") between 1 and 200),
  "program_version" integer,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "user_id" uuid references auth.users (id) on delete cascade,
  -- The program's step ids when it enrolled or last changed.
  "steps" text[] not null default '{}',
  "completed_steps" integer not null default 0 check ("completed_steps" >= 0),
  "status" text not null default 'active' check ("status" in ('active', 'completed', 'cancelled')),
  "enrolled_by" uuid,
  "enrolled_at" timestamptz not null default now(),
  "completed_at" timestamptz,
  "cancelled_at" timestamptz,
  "updated_at" timestamptz not null default now(),
  check (("subject_type" = 'user') = ("user_id" is not null)),
  check ("user_id" is null or "subject_id" = "user_id"::text),
  unique nulls not distinct ("tenant_id", "program", "subject_type", "subject_id")
);
create index if not exists "enrollments_program_idx" on "better_supabase"."enrollments" ("tenant_id", "program", "status");
create index if not exists "enrollments_subject_idx" on "better_supabase"."enrollments" ("tenant_id", "subject_type", "subject_id");
create index if not exists "enrollments_user_idx" on "better_supabase"."enrollments" ("user_id");

create table if not exists "better_supabase"."enrollment_steps" (
  "enrollment_id" uuid not null references "better_supabase"."enrollments" ("id") on delete cascade,
  "tenant_id" uuid,
  "step" text not null,
  "completed_by" uuid,
  "completed_at" timestamptz not null default now(),
  primary key ("enrollment_id", "step")
);

alter table "better_supabase"."enrollment_programs" enable row level security;
revoke all on "better_supabase"."enrollment_programs" from public, anon, authenticated;
grant select on "better_supabase"."enrollment_programs" to authenticated;
grant all on "better_supabase"."enrollment_programs" to service_role;
drop policy if exists "enrollment_programs_read" on "better_supabase"."enrollment_programs";
create policy enrollment_programs_read on "better_supabase"."enrollment_programs"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')));
alter table "better_supabase"."enrollments" enable row level security;
revoke all on "better_supabase"."enrollments" from public, anon, authenticated;
grant select on "better_supabase"."enrollments" to authenticated;
grant all on "better_supabase"."enrollments" to service_role;
drop policy if exists "enrollments_read" on "better_supabase"."enrollments";
create policy enrollments_read on "better_supabase"."enrollments"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')));
alter table "better_supabase"."enrollment_steps" enable row level security;
revoke all on "better_supabase"."enrollment_steps" from public, anon, authenticated;
grant select on "better_supabase"."enrollment_steps" to authenticated;
grant all on "better_supabase"."enrollment_steps" to service_role;
drop policy if exists "enrollment_steps_read" on "better_supabase"."enrollment_steps";
create policy enrollment_steps_read on "better_supabase"."enrollment_steps"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."enrollments" x where x."id" = "better_supabase"."enrollment_steps"."enrollment_id"));

-- An enrollment with its steps and the completed ones, oldest first.
create or replace function "better_supabase"."enrollment_json"(enrollment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id", 'organizationId', x."tenant_id", 'program', x."program", 'programVersion', x."program_version",
    'subjectType', x."subject_type", 'subjectId', x."subject_id", 'status', x."status",
    'steps', to_jsonb(x."steps"), 'completedSteps', x."completed_steps", 'totalSteps', cardinality(x."steps"),
    'enrolledBy', x."enrolled_by", 'enrolledAt', x."enrolled_at", 'completedAt', x."completed_at",
    'cancelledAt', x."cancelled_at", 'updatedAt', x."updated_at",
    'progress', coalesce((
      select jsonb_agg(jsonb_build_object('step', y."step", 'completedAt', y."completed_at", 'completedBy', y."completed_by") order by y."completed_at", array_position(x."steps", y."step"), y."step")
      from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id"
    ), '[]'::jsonb)
  )
  from "better_supabase"."enrollments" x
  where x."id" = enrollment_json.enrollment_id
$$;
revoke execute on function "better_supabase"."enrollment_json"(uuid) from public, anon, authenticated;

-- The enrollment of a subject in a program, created when missing. steps are
-- the program's step ids; when they changed, the enrollment takes them and
-- recounts. For this module and modules that drive their own programs, such
-- as onboarding (program keys with a colon).
create or replace function "better_supabase"."enrollment_ensure"(tenant uuid, program text, program_version integer, steps text[], subject_type text, subject_id text, actor uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."enrollments";
begin
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" is not distinct from enrollment_ensure.tenant and x."program" = enrollment_ensure.program
    and x."subject_type" = enrollment_ensure.subject_type and x."subject_id" = enrollment_ensure.subject_id
  for update;
  if v_row."id" is null then
    insert into "better_supabase"."enrollments" ("tenant_id", "program", "program_version", "subject_type", "subject_id", "user_id", "steps", "enrolled_by")
    values (enrollment_ensure.tenant, enrollment_ensure.program, enrollment_ensure.program_version, enrollment_ensure.subject_type, enrollment_ensure.subject_id, case when enrollment_ensure.subject_type = 'user' then enrollment_ensure.subject_id::uuid end, enrollment_ensure.steps, enrollment_ensure.actor)
    on conflict do nothing
    returning * into v_row;
    if v_row."id" is null then
      select * into v_row from "better_supabase"."enrollments" x
      where x."tenant_id" is not distinct from enrollment_ensure.tenant and x."program" = enrollment_ensure.program
        and x."subject_type" = enrollment_ensure.subject_type and x."subject_id" = enrollment_ensure.subject_id;
      return v_row."id";
    end if;
    return v_row."id";
  end if;
  if v_row."steps" is distinct from enrollment_ensure.steps or v_row."program_version" is distinct from enrollment_ensure.program_version then
    update "better_supabase"."enrollments" x set "steps" = enrollment_ensure.steps, "program_version" = enrollment_ensure.program_version
    where x."id" = v_row."id";
    update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  end if;
  return v_row."id";
end;
$$;
revoke execute on function "better_supabase"."enrollment_ensure"(uuid, text, integer, text[], text, text, uuid) from public, anon, authenticated;

-- Marks a step done or not done without a permission check; false when it
-- already was. Emits enrollment.step_completed and enrollment.completed for
-- enrollments in an organization.
create or replace function "better_supabase"."enrollment_mark"(enrollment_id uuid, step text, done boolean, actor uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."enrollments";
  v_was text;
  v_count integer;
begin
  select * into v_row from "better_supabase"."enrollments" x where x."id" = enrollment_mark.enrollment_id for update;
  if v_row."id" is null then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if enrollment_mark.step is null or not (enrollment_mark.step = any(v_row."steps")) then
    raise exception 'this step is not part of the program' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'cancelled' then
    raise exception 'the enrollment is cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_was := v_row."status";
  if enrollment_mark.done then
    insert into "better_supabase"."enrollment_steps" ("enrollment_id", "tenant_id", "step", "completed_by")
    values (v_row."id", v_row."tenant_id", enrollment_mark.step, enrollment_mark.actor)
    on conflict do nothing;
  else
    delete from "better_supabase"."enrollment_steps" x where x."enrollment_id" = v_row."id" and x."step" = enrollment_mark.step;
  end if;
  get diagnostics v_count = row_count;
  if v_count = 0 then
    return false;
  end if;
  update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if enrollment_mark.done then
    if v_was <> 'completed' and v_row."status" = 'completed' then
      null;
    end if;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."enrollment_mark"(uuid, text, boolean, uuid) from public, anon, authenticated;

-- Creates or changes a program. program is { id?, version?, key, name,
-- description, subjectTypes, steps, enabled }; keys left out keep their value.
-- Changing the steps raises the version. version, when given, must be the
-- stored one.
create or replace function "better_supabase"."save_enrollment_program"(tenant uuid, program jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."enrollment_programs";
  v_row "better_supabase"."enrollment_programs";
  v_key text;
  v_name text;
  v_description text;
  v_types text[];
  v_steps jsonb;
  v_enabled boolean;
  v_step jsonb;
  v_ids text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_enrollment_program.tenant is not null and coalesce(better_supabase.can('tenant', save_enrollment_program.tenant, 'enrollments.manage'), false))) then
    raise exception 'not allowed to manage enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if save_enrollment_program.program is null or jsonb_typeof(save_enrollment_program.program) <> 'object' then
    raise exception 'program must be an object' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_id := nullif(save_enrollment_program.program ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."enrollment_programs" x
    where x."id" = v_id and x."tenant_id" = save_enrollment_program.tenant
    for update;
    if v_old."id" is null then
      raise exception 'enrollment program not found' using errcode = 'P0002', hint = 'ENROLLMENTS_PROGRAM_NOT_FOUND';
    end if;
    if save_enrollment_program.program ? 'version' and (save_enrollment_program.program ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'the program changed since you read it' using errcode = '40001', hint = 'ENROLLMENTS_PROGRAM_CONFLICT';
    end if;
  end if;
  if save_enrollment_program.program ? 'subjectTypes' and jsonb_typeof(save_enrollment_program.program -> 'subjectTypes') <> 'array' then
    raise exception 'subjectTypes must be an array of subject types' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_key := coalesce(save_enrollment_program.program ->> 'key', v_old."key");
  v_name := trim(coalesce(save_enrollment_program.program ->> 'name', v_old."name"));
  v_description := case when save_enrollment_program.program ? 'description'
    then nullif(trim(save_enrollment_program.program ->> 'description'), '') else v_old."description" end;
  v_types := case when save_enrollment_program.program ? 'subjectTypes'
    then array(select t.value from jsonb_array_elements_text(save_enrollment_program.program -> 'subjectTypes') with ordinality as t(value, ord) order by t.ord)
    else coalesce(v_old."subject_types", '{}') end;
  v_steps := case when save_enrollment_program.program ? 'steps'
    then save_enrollment_program.program -> 'steps' else coalesce(v_old."steps", '[]'::jsonb) end;
  v_enabled := case when save_enrollment_program.program ? 'enabled'
    then (save_enrollment_program.program ->> 'enabled')::boolean else coalesce(v_old."enabled", true) end;
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'key: use lowercase letters, digits, "_" or "-", starting with a letter' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_old."id" is not null and v_key <> v_old."key" then
    raise exception 'a program''s key can''t change' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_name is null or length(v_name) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if length(v_description) > 2000 then
    raise exception 'description must be at most 2000 characters' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if exists (select 1 from unnest(v_types) as t(value) where t.value is null or t.value !~ '^[a-z][a-z0-9_-]{0,62}$') then
    raise exception 'subjectTypes must be lower-case subject types' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) = 0 then
    raise exception 'steps: pass at least one step' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if jsonb_array_length(v_steps) > 100 then
    raise exception 'a program holds at most 100 steps' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  for v_step in select t.value from jsonb_array_elements(v_steps) as t(value) loop
    if jsonb_typeof(v_step) <> 'object' or coalesce(v_step ->> 'id', '') !~ '^[a-z][a-z0-9_.-]{0,63}$' then
      raise exception 'each step needs an id of lowercase letters, digits, "_", "." or "-"' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    if (v_step ->> 'id') = any(v_ids) then
      raise exception 'step ids must be unique' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    if length(v_step ->> 'title') > 200 or length(v_step ->> 'description') > 2000 then
      raise exception 'a step title holds at most 200 characters and a description 2000' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    v_ids := v_ids || (v_step ->> 'id');
  end loop;
  v_steps := (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', t.value ->> 'id', 'title', t.value ->> 'title', 'description', t.value ->> 'description')) order by t.ord)
    from jsonb_array_elements(v_steps) with ordinality as t(value, ord)
  );
  if v_old."id" is null then
    insert into "better_supabase"."enrollment_programs" ("tenant_id", "key", "name", "description", "subject_types", "steps", "enabled", "created_by")
    values (save_enrollment_program.tenant, v_key, v_name, v_description, v_types, v_steps, v_enabled, auth.uid())
    on conflict ("tenant_id", "key") do nothing
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'a program with this key already exists' using errcode = '23505', hint = 'ENROLLMENTS_PROGRAM_EXISTS';
    end if;
  else
    update "better_supabase"."enrollment_programs" x
    set "name" = v_name, "description" = v_description, "subject_types" = v_types, "steps" = v_steps,
      "enabled" = v_enabled,
      "version" = x."version" + case when x."steps" is distinct from v_steps then 1 else 0 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectTypes', to_jsonb(v_row."subject_types"), 'steps', v_row."steps", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_enrollment_program"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_enrollment_program"(uuid, jsonb) to authenticated, service_role;

-- The organization's programs by key.
create or replace function "better_supabase"."enrollment_programs"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enrollment_programs.tenant is not null and coalesce(better_supabase.can('tenant', enrollment_programs.tenant, 'enrollments.read'), false))) then
    raise exception 'not allowed to read enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectTypes', to_jsonb(x."subject_types"), 'steps', x."steps", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."key")
    from "better_supabase"."enrollment_programs" x where x."tenant_id" = enrollment_programs.tenant
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."enrollment_programs"(uuid) from public, anon;
grant execute on function "better_supabase"."enrollment_programs"(uuid) to authenticated, service_role;

-- Deletes a program with its enrollments; false when it was already gone.
create or replace function "better_supabase"."delete_enrollment_program"(program_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."enrollment_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."enrollment_programs" x where x."id" = delete_enrollment_program.program_id for update;
  if v_row."id" is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.manage'), false))) then
    raise exception 'not allowed to manage enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  delete from "better_supabase"."enrollments" x where x."tenant_id" = v_row."tenant_id" and x."program" = v_row."key";
  delete from "better_supabase"."enrollment_programs" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_enrollment_program"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_enrollment_program"(uuid) to authenticated, service_role;

-- Enrolls a subject in a program; returns the enrollment. Enrolling an
-- enrolled subject returns its enrollment, and enrolling a cancelled one
-- starts it again with its completed steps.
create or replace function "better_supabase"."enroll"(tenant uuid, program text, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_program "better_supabase"."enrollment_programs";
  v_row "better_supabase"."enrollments";
  v_id uuid;
  v_steps text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enroll.tenant is not null and coalesce(better_supabase.can('tenant', enroll.tenant, 'enrollments.enroll'), false))) then
    raise exception 'not allowed to enroll' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  select * into v_program from "better_supabase"."enrollment_programs" x
  where x."tenant_id" = enroll.tenant and x."key" = enroll.program;
  if v_program."id" is null then
    raise exception 'enrollment program not found' using errcode = 'P0002', hint = 'ENROLLMENTS_PROGRAM_NOT_FOUND';
  end if;
  if not v_program."enabled" then
    raise exception 'this program is turned off' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if enroll.subject_type is null or enroll.subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' or enroll.subject_id is null or length(enroll.subject_id) not between 1 and 200 then
    raise exception 'an enrollment needs a subject type and id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if cardinality(v_program."subject_types") > 0 and not (enroll.subject_type = any(v_program."subject_types")) then
    raise exception 'this program doesn''t enroll this subject type' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if enroll.subject_type = 'user' and enroll.subject_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'a user subject needs a user id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_steps := array(select t.value ->> 'id' from jsonb_array_elements(v_program."steps") with ordinality as t(value, ord) order by t.ord);
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = enroll.tenant and x."program" = enroll.program
    and x."subject_type" = enroll.subject_type and x."subject_id" = enroll.subject_id
  for update;
  if v_row."status" = 'cancelled' then
    update "better_supabase"."enrollments" x
    set "status" = 'active', "cancelled_at" = null, "enrolled_by" = auth.uid(), "enrolled_at" = now(),
      "steps" = v_steps, "program_version" = v_program."version"
    where x."id" = v_row."id";
    update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
    v_id := v_row."id";
  else
    v_id := "better_supabase"."enrollment_ensure"(enroll.tenant, enroll.program, v_program."version", v_steps, enroll.subject_type, enroll.subject_id, auth.uid());
  end if;
  return "better_supabase"."enrollment_json"(v_id);
end;
$$;
revoke execute on function "better_supabase"."enroll"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."enroll"(uuid, text, text, text) to authenticated, service_role;

-- A subject's enrollment in a program, or null. A user reads their own.
create or replace function "better_supabase"."enrollment"(tenant uuid, program text, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enrollment.tenant is not null and coalesce(better_supabase.can('tenant', enrollment.tenant, 'enrollments.read'), false))) or (enrollment.subject_type = 'user' and enrollment.subject_id = auth.uid()::text)) then
    raise exception 'not allowed to read enrollments' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  select x."id" into v_id from "better_supabase"."enrollments" x
  where x."tenant_id" = enrollment.tenant and x."program" = enrollment.program
    and x."subject_type" = enrollment.subject_type and x."subject_id" = enrollment.subject_id;
  return case when v_id is null then null else "better_supabase"."enrollment_json"(v_id) end;
end;
$$;
revoke execute on function "better_supabase"."enrollment"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."enrollment"(uuid, text, text, text) to authenticated, service_role;

-- The organization's enrollments, most recently changed first. Without
-- enrollments.read a member sees only their own.
create or replace function "better_supabase"."list_enrollments"(tenant uuid, program text default null, subject_type text default null, subject_id text default null, status text default null, page_size integer default null, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_read boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', list_enrollments.tenant, 'enrollments.read'), false)));
begin
  if not v_read and auth.uid() is null then
    raise exception 'not allowed to read enrollments' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if list_enrollments.status is not null and list_enrollments.status not in ('active', 'completed', 'cancelled') then
    raise exception 'status must be active, completed or cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  return coalesce((
    select jsonb_agg("better_supabase"."enrollment_json"(y."id") order by y."updated_at" desc, y."id")
    from (
      select x."id", x."updated_at" from "better_supabase"."enrollments" x
      where x."tenant_id" = list_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (list_enrollments.program is null or x."program" = list_enrollments.program)
        and (list_enrollments.subject_type is null or x."subject_type" = list_enrollments.subject_type)
        and (list_enrollments.subject_id is null or x."subject_id" = list_enrollments.subject_id)
        and (list_enrollments.status is null or x."status" = list_enrollments.status)
        and (list_enrollments.before is null or x."updated_at" < list_enrollments.before)
      order by x."updated_at" desc, x."id"
      limit least(greatest(coalesce(list_enrollments.page_size, 50), 1), 200)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_enrollments"(uuid, text, text, text, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_enrollments"(uuid, text, text, text, text, integer, timestamptz) to authenticated, service_role;

-- Marks a step of an enrollment done or not done: enrollments.enroll, or the
-- enrolled user for their own.
create or replace function "better_supabase"."enrollment_step"(enrollment_id uuid, step text, done boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."enrollments";
begin
  select * into v_row from "better_supabase"."enrollments" x where x."id" = enrollment_step.enrollment_id;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.read'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.enroll'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'not allowed to change this enrollment' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  -- A course's steps follow its lessons, so they change only through courses.
  if v_row."program" like 'course:%' then
    raise exception 'this enrollment belongs to a course; complete its lessons through courses' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  -- A sequence's steps run on its schedule, so only its runner marks them.
  if v_row."program" like 'sequence:%' then
    raise exception 'this enrollment belongs to a sequence; its steps run on the sequence''s schedule' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  perform "better_supabase"."enrollment_mark"(v_row."id", enrollment_step.step, enrollment_step.done, auth.uid());
  return "better_supabase"."enrollment_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."enrollment_step"(uuid, text, boolean) from public, anon, authenticated;

create or replace function "better_supabase"."complete_enrollment_step"(enrollment_id uuid, step text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."enrollment_step"(complete_enrollment_step.enrollment_id, complete_enrollment_step.step, true)
$$;
revoke execute on function "better_supabase"."complete_enrollment_step"(uuid, text) from public, anon;
grant execute on function "better_supabase"."complete_enrollment_step"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."reset_enrollment_step"(enrollment_id uuid, step text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."enrollment_step"(reset_enrollment_step.enrollment_id, reset_enrollment_step.step, false)
$$;
revoke execute on function "better_supabase"."reset_enrollment_step"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reset_enrollment_step"(uuid, text) to authenticated, service_role;

-- Cancels an active enrollment; its completed steps stay. A cancelled one is
-- returned as it is. Programs a module drives can't be cancelled.
create or replace function "better_supabase"."cancel_enrollment"(enrollment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."enrollments" x where x."id" = cancel_enrollment.enrollment_id for update;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.read'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.enroll'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'not allowed to change this enrollment' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if position(':' in v_row."program") > 0 then
    raise exception 'this enrollment belongs to a module and can''t be cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'completed' then
    raise exception 'a completed enrollment can''t be cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'active' then
    update "better_supabase"."enrollments" x
    set "status" = 'cancelled', "cancelled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  return "better_supabase"."enrollment_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."cancel_enrollment"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_enrollment"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_programs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_select on "better_supabase"."enrollment_programs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_insert on "better_supabase"."enrollment_programs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_update on "better_supabase"."enrollment_programs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_delete on "better_supabase"."enrollment_programs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."enrollments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollments";
create policy bsb_tenant_scope_select on "better_supabase"."enrollments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollments";
create policy bsb_tenant_scope_insert on "better_supabase"."enrollments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollments";
create policy bsb_tenant_scope_update on "better_supabase"."enrollments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollments";
create policy bsb_tenant_scope_delete on "better_supabase"."enrollments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_steps";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_select on "better_supabase"."enrollment_steps" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."enrollments" x where x."id" = "better_supabase"."enrollment_steps"."enrollment_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_insert on "better_supabase"."enrollment_steps" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_update on "better_supabase"."enrollment_steps" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_delete on "better_supabase"."enrollment_steps" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_036_enrollments.sql
-- better-supabase module: enrollments
-- @bsb-block-data enrollments
-- @bsb-hash sha256:ba27786140fd499c4d1e2ab814ef20ead1970f014ec0279b82377d83afb2017a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('enrollments', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_036_enrollments.sql
-- better-supabase module: enrollments
-- @bsb-block enrollments@1 managed
-- @bsb-hash sha256:952f78f10c046dcbb3c79e8f7d2f0e9f6573a396f6fd790f280dea3fba137fb9
-- Programs of steps per organization, and enrollments of a party, a member or any subject in them with step progress and completion. Onboarding checklists run on it.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_programs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_steps";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."enrollment_programs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  -- The subject types it enrolls; empty enrolls any.
  "subject_types" text[] not null default '{}',
  -- [{ id, title, description }], in order.
  "steps" jsonb not null default '[]'::jsonb check (jsonb_typeof("steps") = 'array'),
  "enabled" boolean not null default true,
  "version" integer not null default 1,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);

-- One per program and subject. A user's own onboarding checklist has no
-- tenant; user_id is set for user subjects so the row goes with the user.
create table if not exists "better_supabase"."enrollments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "program" text not null check (length("program") between 1 and 200),
  "program_version" integer,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "user_id" uuid references auth.users (id) on delete cascade,
  -- The program's step ids when it enrolled or last changed.
  "steps" text[] not null default '{}',
  "completed_steps" integer not null default 0 check ("completed_steps" >= 0),
  "status" text not null default 'active' check ("status" in ('active', 'completed', 'cancelled')),
  "enrolled_by" uuid,
  "enrolled_at" timestamptz not null default now(),
  "completed_at" timestamptz,
  "cancelled_at" timestamptz,
  "updated_at" timestamptz not null default now(),
  check (("subject_type" = 'user') = ("user_id" is not null)),
  check ("user_id" is null or "subject_id" = "user_id"::text),
  unique nulls not distinct ("tenant_id", "program", "subject_type", "subject_id")
);
create index if not exists "enrollments_program_idx" on "better_supabase"."enrollments" ("tenant_id", "program", "status");
create index if not exists "enrollments_subject_idx" on "better_supabase"."enrollments" ("tenant_id", "subject_type", "subject_id");
create index if not exists "enrollments_user_idx" on "better_supabase"."enrollments" ("user_id");

create table if not exists "better_supabase"."enrollment_steps" (
  "enrollment_id" uuid not null references "better_supabase"."enrollments" ("id") on delete cascade,
  "tenant_id" uuid,
  "step" text not null,
  "completed_by" uuid,
  "completed_at" timestamptz not null default now(),
  primary key ("enrollment_id", "step")
);

alter table "better_supabase"."enrollment_programs" enable row level security;
revoke all on "better_supabase"."enrollment_programs" from public, anon, authenticated;
grant select on "better_supabase"."enrollment_programs" to authenticated;
grant all on "better_supabase"."enrollment_programs" to service_role;
drop policy if exists "enrollment_programs_read" on "better_supabase"."enrollment_programs";
create policy enrollment_programs_read on "better_supabase"."enrollment_programs"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')));
alter table "better_supabase"."enrollments" enable row level security;
revoke all on "better_supabase"."enrollments" from public, anon, authenticated;
grant select on "better_supabase"."enrollments" to authenticated;
grant all on "better_supabase"."enrollments" to service_role;
drop policy if exists "enrollments_read" on "better_supabase"."enrollments";
create policy enrollments_read on "better_supabase"."enrollments"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')));
alter table "better_supabase"."enrollment_steps" enable row level security;
revoke all on "better_supabase"."enrollment_steps" from public, anon, authenticated;
grant select on "better_supabase"."enrollment_steps" to authenticated;
grant all on "better_supabase"."enrollment_steps" to service_role;
drop policy if exists "enrollment_steps_read" on "better_supabase"."enrollment_steps";
create policy enrollment_steps_read on "better_supabase"."enrollment_steps"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."enrollments" x where x."id" = "better_supabase"."enrollment_steps"."enrollment_id"));

-- An enrollment with its steps and the completed ones, oldest first.
create or replace function "better_supabase"."enrollment_json"(enrollment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id", 'organizationId', x."tenant_id", 'program', x."program", 'programVersion', x."program_version",
    'subjectType', x."subject_type", 'subjectId', x."subject_id", 'status', x."status",
    'steps', to_jsonb(x."steps"), 'completedSteps', x."completed_steps", 'totalSteps', cardinality(x."steps"),
    'enrolledBy', x."enrolled_by", 'enrolledAt', x."enrolled_at", 'completedAt', x."completed_at",
    'cancelledAt', x."cancelled_at", 'updatedAt', x."updated_at",
    'progress', coalesce((
      select jsonb_agg(jsonb_build_object('step', y."step", 'completedAt', y."completed_at", 'completedBy', y."completed_by") order by y."completed_at", array_position(x."steps", y."step"), y."step")
      from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id"
    ), '[]'::jsonb)
  )
  from "better_supabase"."enrollments" x
  where x."id" = enrollment_json.enrollment_id
$$;
revoke execute on function "better_supabase"."enrollment_json"(uuid) from public, anon, authenticated;

-- The enrollment of a subject in a program, created when missing. steps are
-- the program's step ids; when they changed, the enrollment takes them and
-- recounts. For this module and modules that drive their own programs, such
-- as onboarding (program keys with a colon).
create or replace function "better_supabase"."enrollment_ensure"(tenant uuid, program text, program_version integer, steps text[], subject_type text, subject_id text, actor uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."enrollments";
begin
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" is not distinct from enrollment_ensure.tenant and x."program" = enrollment_ensure.program
    and x."subject_type" = enrollment_ensure.subject_type and x."subject_id" = enrollment_ensure.subject_id
  for update;
  if v_row."id" is null then
    insert into "better_supabase"."enrollments" ("tenant_id", "program", "program_version", "subject_type", "subject_id", "user_id", "steps", "enrolled_by")
    values (enrollment_ensure.tenant, enrollment_ensure.program, enrollment_ensure.program_version, enrollment_ensure.subject_type, enrollment_ensure.subject_id, case when enrollment_ensure.subject_type = 'user' then enrollment_ensure.subject_id::uuid end, enrollment_ensure.steps, enrollment_ensure.actor)
    on conflict do nothing
    returning * into v_row;
    if v_row."id" is null then
      select * into v_row from "better_supabase"."enrollments" x
      where x."tenant_id" is not distinct from enrollment_ensure.tenant and x."program" = enrollment_ensure.program
        and x."subject_type" = enrollment_ensure.subject_type and x."subject_id" = enrollment_ensure.subject_id;
      return v_row."id";
    end if;
  if v_row."tenant_id" is not null then
    perform "better_supabase".emit_event('enrollment.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'program', v_row."program", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'step', null::text, 'completedSteps', v_row."completed_steps", 'totalSteps', cardinality(v_row."steps")), 'enrollments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  end if;
    return v_row."id";
  end if;
  if v_row."steps" is distinct from enrollment_ensure.steps or v_row."program_version" is distinct from enrollment_ensure.program_version then
    update "better_supabase"."enrollments" x set "steps" = enrollment_ensure.steps, "program_version" = enrollment_ensure.program_version
    where x."id" = v_row."id";
    update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  end if;
  return v_row."id";
end;
$$;
revoke execute on function "better_supabase"."enrollment_ensure"(uuid, text, integer, text[], text, text, uuid) from public, anon, authenticated;

-- Marks a step done or not done without a permission check; false when it
-- already was. Emits enrollment.step_completed and enrollment.completed for
-- enrollments in an organization.
create or replace function "better_supabase"."enrollment_mark"(enrollment_id uuid, step text, done boolean, actor uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."enrollments";
  v_was text;
  v_count integer;
begin
  select * into v_row from "better_supabase"."enrollments" x where x."id" = enrollment_mark.enrollment_id for update;
  if v_row."id" is null then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if enrollment_mark.step is null or not (enrollment_mark.step = any(v_row."steps")) then
    raise exception 'this step is not part of the program' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'cancelled' then
    raise exception 'the enrollment is cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_was := v_row."status";
  if enrollment_mark.done then
    insert into "better_supabase"."enrollment_steps" ("enrollment_id", "tenant_id", "step", "completed_by")
    values (v_row."id", v_row."tenant_id", enrollment_mark.step, enrollment_mark.actor)
    on conflict do nothing;
  else
    delete from "better_supabase"."enrollment_steps" x where x."enrollment_id" = v_row."id" and x."step" = enrollment_mark.step;
  end if;
  get diagnostics v_count = row_count;
  if v_count = 0 then
    return false;
  end if;
  update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if enrollment_mark.done then
  if v_row."tenant_id" is not null then
    perform "better_supabase".emit_event('enrollment.step_completed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'program', v_row."program", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'step', enrollment_mark.step, 'completedSteps', v_row."completed_steps", 'totalSteps', cardinality(v_row."steps")), 'enrollments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  end if;
    if v_was <> 'completed' and v_row."status" = 'completed' then
  if v_row."tenant_id" is not null then
    perform "better_supabase".emit_event('enrollment.completed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'program', v_row."program", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'step', null::text, 'completedSteps', v_row."completed_steps", 'totalSteps', cardinality(v_row."steps")), 'enrollments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  end if;
      null;
    end if;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."enrollment_mark"(uuid, text, boolean, uuid) from public, anon, authenticated;

-- Creates or changes a program. program is { id?, version?, key, name,
-- description, subjectTypes, steps, enabled }; keys left out keep their value.
-- Changing the steps raises the version. version, when given, must be the
-- stored one.
create or replace function "better_supabase"."save_enrollment_program"(tenant uuid, program jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."enrollment_programs";
  v_row "better_supabase"."enrollment_programs";
  v_key text;
  v_name text;
  v_description text;
  v_types text[];
  v_steps jsonb;
  v_enabled boolean;
  v_step jsonb;
  v_ids text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_enrollment_program.tenant is not null and coalesce(better_supabase.can('tenant', save_enrollment_program.tenant, 'enrollments.manage'), false))) then
    raise exception 'not allowed to manage enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if save_enrollment_program.program is null or jsonb_typeof(save_enrollment_program.program) <> 'object' then
    raise exception 'program must be an object' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_id := nullif(save_enrollment_program.program ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."enrollment_programs" x
    where x."id" = v_id and x."tenant_id" = save_enrollment_program.tenant
    for update;
    if v_old."id" is null then
      raise exception 'enrollment program not found' using errcode = 'P0002', hint = 'ENROLLMENTS_PROGRAM_NOT_FOUND';
    end if;
    if save_enrollment_program.program ? 'version' and (save_enrollment_program.program ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'the program changed since you read it' using errcode = '40001', hint = 'ENROLLMENTS_PROGRAM_CONFLICT';
    end if;
  end if;
  if save_enrollment_program.program ? 'subjectTypes' and jsonb_typeof(save_enrollment_program.program -> 'subjectTypes') <> 'array' then
    raise exception 'subjectTypes must be an array of subject types' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_key := coalesce(save_enrollment_program.program ->> 'key', v_old."key");
  v_name := trim(coalesce(save_enrollment_program.program ->> 'name', v_old."name"));
  v_description := case when save_enrollment_program.program ? 'description'
    then nullif(trim(save_enrollment_program.program ->> 'description'), '') else v_old."description" end;
  v_types := case when save_enrollment_program.program ? 'subjectTypes'
    then array(select t.value from jsonb_array_elements_text(save_enrollment_program.program -> 'subjectTypes') with ordinality as t(value, ord) order by t.ord)
    else coalesce(v_old."subject_types", '{}') end;
  v_steps := case when save_enrollment_program.program ? 'steps'
    then save_enrollment_program.program -> 'steps' else coalesce(v_old."steps", '[]'::jsonb) end;
  v_enabled := case when save_enrollment_program.program ? 'enabled'
    then (save_enrollment_program.program ->> 'enabled')::boolean else coalesce(v_old."enabled", true) end;
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'key: use lowercase letters, digits, "_" or "-", starting with a letter' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_old."id" is not null and v_key <> v_old."key" then
    raise exception 'a program''s key can''t change' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_name is null or length(v_name) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if length(v_description) > 2000 then
    raise exception 'description must be at most 2000 characters' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if exists (select 1 from unnest(v_types) as t(value) where t.value is null or t.value !~ '^[a-z][a-z0-9_-]{0,62}$') then
    raise exception 'subjectTypes must be lower-case subject types' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) = 0 then
    raise exception 'steps: pass at least one step' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if jsonb_array_length(v_steps) > 100 then
    raise exception 'a program holds at most 100 steps' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  for v_step in select t.value from jsonb_array_elements(v_steps) as t(value) loop
    if jsonb_typeof(v_step) <> 'object' or coalesce(v_step ->> 'id', '') !~ '^[a-z][a-z0-9_.-]{0,63}$' then
      raise exception 'each step needs an id of lowercase letters, digits, "_", "." or "-"' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    if (v_step ->> 'id') = any(v_ids) then
      raise exception 'step ids must be unique' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    if length(v_step ->> 'title') > 200 or length(v_step ->> 'description') > 2000 then
      raise exception 'a step title holds at most 200 characters and a description 2000' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    v_ids := v_ids || (v_step ->> 'id');
  end loop;
  v_steps := (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', t.value ->> 'id', 'title', t.value ->> 'title', 'description', t.value ->> 'description')) order by t.ord)
    from jsonb_array_elements(v_steps) with ordinality as t(value, ord)
  );
  if v_old."id" is null then
    insert into "better_supabase"."enrollment_programs" ("tenant_id", "key", "name", "description", "subject_types", "steps", "enabled", "created_by")
    values (save_enrollment_program.tenant, v_key, v_name, v_description, v_types, v_steps, v_enabled, auth.uid())
    on conflict ("tenant_id", "key") do nothing
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'a program with this key already exists' using errcode = '23505', hint = 'ENROLLMENTS_PROGRAM_EXISTS';
    end if;
  else
    update "better_supabase"."enrollment_programs" x
    set "name" = v_name, "description" = v_description, "subject_types" = v_types, "steps" = v_steps,
      "enabled" = v_enabled,
      "version" = x."version" + case when x."steps" is distinct from v_steps then 1 else 0 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  perform "better_supabase".emit_event('enrollment_program.saved', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version"), 'enrollment-programs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  perform better_supabase.audit_event(
    event_type => 'enrollment_program.saved',
    category => 'data',
    target_type => 'enrollment_program',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'saved an enrollment program',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectTypes', to_jsonb(v_row."subject_types"), 'steps', v_row."steps", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_enrollment_program"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_enrollment_program"(uuid, jsonb) to authenticated, service_role;

-- The organization's programs by key.
create or replace function "better_supabase"."enrollment_programs"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enrollment_programs.tenant is not null and coalesce(better_supabase.can('tenant', enrollment_programs.tenant, 'enrollments.read'), false))) then
    raise exception 'not allowed to read enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectTypes', to_jsonb(x."subject_types"), 'steps', x."steps", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."key")
    from "better_supabase"."enrollment_programs" x where x."tenant_id" = enrollment_programs.tenant
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."enrollment_programs"(uuid) from public, anon;
grant execute on function "better_supabase"."enrollment_programs"(uuid) to authenticated, service_role;

-- Deletes a program with its enrollments; false when it was already gone.
create or replace function "better_supabase"."delete_enrollment_program"(program_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."enrollment_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."enrollment_programs" x where x."id" = delete_enrollment_program.program_id for update;
  if v_row."id" is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.manage'), false))) then
    raise exception 'not allowed to manage enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  delete from "better_supabase"."enrollments" x where x."tenant_id" = v_row."tenant_id" and x."program" = v_row."key";
  delete from "better_supabase"."enrollment_programs" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('enrollment_program.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version"), 'enrollment-programs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  perform better_supabase.audit_event(
    event_type => 'enrollment_program.deleted',
    category => 'data',
    target_type => 'enrollment_program',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'deleted an enrollment program',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_enrollment_program"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_enrollment_program"(uuid) to authenticated, service_role;

-- Enrolls a subject in a program; returns the enrollment. Enrolling an
-- enrolled subject returns its enrollment, and enrolling a cancelled one
-- starts it again with its completed steps.
create or replace function "better_supabase"."enroll"(tenant uuid, program text, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_program "better_supabase"."enrollment_programs";
  v_row "better_supabase"."enrollments";
  v_id uuid;
  v_steps text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enroll.tenant is not null and coalesce(better_supabase.can('tenant', enroll.tenant, 'enrollments.enroll'), false))) then
    raise exception 'not allowed to enroll' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  select * into v_program from "better_supabase"."enrollment_programs" x
  where x."tenant_id" = enroll.tenant and x."key" = enroll.program;
  if v_program."id" is null then
    raise exception 'enrollment program not found' using errcode = 'P0002', hint = 'ENROLLMENTS_PROGRAM_NOT_FOUND';
  end if;
  if not v_program."enabled" then
    raise exception 'this program is turned off' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if enroll.subject_type is null or enroll.subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' or enroll.subject_id is null or length(enroll.subject_id) not between 1 and 200 then
    raise exception 'an enrollment needs a subject type and id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if cardinality(v_program."subject_types") > 0 and not (enroll.subject_type = any(v_program."subject_types")) then
    raise exception 'this program doesn''t enroll this subject type' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if enroll.subject_type = 'user' and enroll.subject_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'a user subject needs a user id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_steps := array(select t.value ->> 'id' from jsonb_array_elements(v_program."steps") with ordinality as t(value, ord) order by t.ord);
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = enroll.tenant and x."program" = enroll.program
    and x."subject_type" = enroll.subject_type and x."subject_id" = enroll.subject_id
  for update;
  if v_row."status" = 'cancelled' then
    update "better_supabase"."enrollments" x
    set "status" = 'active', "cancelled_at" = null, "enrolled_by" = auth.uid(), "enrolled_at" = now(),
      "steps" = v_steps, "program_version" = v_program."version"
    where x."id" = v_row."id";
    update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."tenant_id" is not null then
    perform "better_supabase".emit_event('enrollment.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'program', v_row."program", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'step', null::text, 'completedSteps', v_row."completed_steps", 'totalSteps', cardinality(v_row."steps")), 'enrollments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  end if;
    v_id := v_row."id";
  else
    v_id := "better_supabase"."enrollment_ensure"(enroll.tenant, enroll.program, v_program."version", v_steps, enroll.subject_type, enroll.subject_id, auth.uid());
  end if;
  return "better_supabase"."enrollment_json"(v_id);
end;
$$;
revoke execute on function "better_supabase"."enroll"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."enroll"(uuid, text, text, text) to authenticated, service_role;

-- A subject's enrollment in a program, or null. A user reads their own.
create or replace function "better_supabase"."enrollment"(tenant uuid, program text, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enrollment.tenant is not null and coalesce(better_supabase.can('tenant', enrollment.tenant, 'enrollments.read'), false))) or (enrollment.subject_type = 'user' and enrollment.subject_id = auth.uid()::text)) then
    raise exception 'not allowed to read enrollments' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  select x."id" into v_id from "better_supabase"."enrollments" x
  where x."tenant_id" = enrollment.tenant and x."program" = enrollment.program
    and x."subject_type" = enrollment.subject_type and x."subject_id" = enrollment.subject_id;
  return case when v_id is null then null else "better_supabase"."enrollment_json"(v_id) end;
end;
$$;
revoke execute on function "better_supabase"."enrollment"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."enrollment"(uuid, text, text, text) to authenticated, service_role;

-- The organization's enrollments, most recently changed first. Without
-- enrollments.read a member sees only their own.
create or replace function "better_supabase"."list_enrollments"(tenant uuid, program text default null, subject_type text default null, subject_id text default null, status text default null, page_size integer default null, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_read boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', list_enrollments.tenant, 'enrollments.read'), false)));
begin
  if not v_read and auth.uid() is null then
    raise exception 'not allowed to read enrollments' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if list_enrollments.status is not null and list_enrollments.status not in ('active', 'completed', 'cancelled') then
    raise exception 'status must be active, completed or cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  return coalesce((
    select jsonb_agg("better_supabase"."enrollment_json"(y."id") order by y."updated_at" desc, y."id")
    from (
      select x."id", x."updated_at" from "better_supabase"."enrollments" x
      where x."tenant_id" = list_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (list_enrollments.program is null or x."program" = list_enrollments.program)
        and (list_enrollments.subject_type is null or x."subject_type" = list_enrollments.subject_type)
        and (list_enrollments.subject_id is null or x."subject_id" = list_enrollments.subject_id)
        and (list_enrollments.status is null or x."status" = list_enrollments.status)
        and (list_enrollments.before is null or x."updated_at" < list_enrollments.before)
      order by x."updated_at" desc, x."id"
      limit least(greatest(coalesce(list_enrollments.page_size, 50), 1), 200)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_enrollments"(uuid, text, text, text, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_enrollments"(uuid, text, text, text, text, integer, timestamptz) to authenticated, service_role;

-- Marks a step of an enrollment done or not done: enrollments.enroll, or the
-- enrolled user for their own.
create or replace function "better_supabase"."enrollment_step"(enrollment_id uuid, step text, done boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."enrollments";
begin
  select * into v_row from "better_supabase"."enrollments" x where x."id" = enrollment_step.enrollment_id;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.read'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.enroll'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'not allowed to change this enrollment' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  -- A course's steps follow its lessons, so they change only through courses.
  if v_row."program" like 'course:%' then
    raise exception 'this enrollment belongs to a course; complete its lessons through courses' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  -- A sequence's steps run on its schedule, so only its runner marks them.
  if v_row."program" like 'sequence:%' then
    raise exception 'this enrollment belongs to a sequence; its steps run on the sequence''s schedule' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  perform "better_supabase"."enrollment_mark"(v_row."id", enrollment_step.step, enrollment_step.done, auth.uid());
  return "better_supabase"."enrollment_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."enrollment_step"(uuid, text, boolean) from public, anon, authenticated;

create or replace function "better_supabase"."complete_enrollment_step"(enrollment_id uuid, step text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."enrollment_step"(complete_enrollment_step.enrollment_id, complete_enrollment_step.step, true)
$$;
revoke execute on function "better_supabase"."complete_enrollment_step"(uuid, text) from public, anon;
grant execute on function "better_supabase"."complete_enrollment_step"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."reset_enrollment_step"(enrollment_id uuid, step text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."enrollment_step"(reset_enrollment_step.enrollment_id, reset_enrollment_step.step, false)
$$;
revoke execute on function "better_supabase"."reset_enrollment_step"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reset_enrollment_step"(uuid, text) to authenticated, service_role;

-- Cancels an active enrollment; its completed steps stay. A cancelled one is
-- returned as it is. Programs a module drives can't be cancelled.
create or replace function "better_supabase"."cancel_enrollment"(enrollment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."enrollments" x where x."id" = cancel_enrollment.enrollment_id for update;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.read'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.enroll'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'not allowed to change this enrollment' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if position(':' in v_row."program") > 0 then
    raise exception 'this enrollment belongs to a module and can''t be cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'completed' then
    raise exception 'a completed enrollment can''t be cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'active' then
    update "better_supabase"."enrollments" x
    set "status" = 'cancelled', "cancelled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  if v_row."tenant_id" is not null then
    perform "better_supabase".emit_event('enrollment.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'program', v_row."program", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'step', null::text, 'completedSteps', v_row."completed_steps", 'totalSteps', cardinality(v_row."steps")), 'enrollments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  end if;
  end if;
  return "better_supabase"."enrollment_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."cancel_enrollment"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_enrollment"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_programs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_select on "better_supabase"."enrollment_programs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_insert on "better_supabase"."enrollment_programs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_update on "better_supabase"."enrollment_programs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_delete on "better_supabase"."enrollment_programs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."enrollments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollments";
create policy bsb_tenant_scope_select on "better_supabase"."enrollments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollments";
create policy bsb_tenant_scope_insert on "better_supabase"."enrollments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollments";
create policy bsb_tenant_scope_update on "better_supabase"."enrollments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollments";
create policy bsb_tenant_scope_delete on "better_supabase"."enrollments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_steps";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_select on "better_supabase"."enrollment_steps" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."enrollments" x where x."id" = "better_supabase"."enrollment_steps"."enrollment_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_insert on "better_supabase"."enrollment_steps" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_update on "better_supabase"."enrollment_steps" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_delete on "better_supabase"."enrollment_steps" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_036_enrollments.sql
-- better-supabase module: enrollments
-- @bsb-block-data enrollments
-- @bsb-hash sha256:ba27786140fd499c4d1e2ab814ef20ead1970f014ec0279b82377d83afb2017a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('enrollments', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_036_enrollments.sql
-- better-supabase module: enrollments
-- @bsb-block enrollments@1 managed
-- @bsb-hash sha256:2f120c947e3bec8437f4942d7e8baebabdf2f0f4e5849c1ac69a970d10ff46ab
-- Programs of steps per organization, and enrollments of a party, a member or any subject in them with step progress and completion. Onboarding checklists run on it.
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
    drop policy if exists bsb_tenant_scope on "app_private"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_select on "app_private"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_update on "app_private"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."enrollment_programs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."enrollments";
    drop policy if exists bsb_tenant_scope_select on "app_private"."enrollments";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."enrollments";
    drop policy if exists bsb_tenant_scope_update on "app_private"."enrollments";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."enrollments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_select on "app_private"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_update on "app_private"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."enrollment_steps";
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
create table if not exists "app_private"."enrollment_programs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  -- The subject types it enrolls; empty enrolls any.
  "subject_types" text[] not null default '{}',
  -- [{ id, title, description }], in order.
  "steps" jsonb not null default '[]'::jsonb check (jsonb_typeof("steps") = 'array'),
  "enabled" boolean not null default true,
  "version" integer not null default 1,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);

-- One per program and subject. A user's own onboarding checklist has no
-- tenant; user_id is set for user subjects so the row goes with the user.
create table if not exists "app_private"."enrollments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "program" text not null check (length("program") between 1 and 200),
  "program_version" integer,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "user_id" uuid references auth.users (id) on delete cascade,
  -- The program's step ids when it enrolled or last changed.
  "steps" text[] not null default '{}',
  "completed_steps" integer not null default 0 check ("completed_steps" >= 0),
  "status" text not null default 'active' check ("status" in ('active', 'completed', 'cancelled')),
  "enrolled_by" uuid,
  "enrolled_at" timestamptz not null default now(),
  "completed_at" timestamptz,
  "cancelled_at" timestamptz,
  "updated_at" timestamptz not null default now(),
  check (("subject_type" = 'user') = ("user_id" is not null)),
  check ("user_id" is null or "subject_id" = "user_id"::text),
  unique nulls not distinct ("tenant_id", "program", "subject_type", "subject_id")
);
create index if not exists "enrollments_program_idx" on "app_private"."enrollments" ("tenant_id", "program", "status");
create index if not exists "enrollments_subject_idx" on "app_private"."enrollments" ("tenant_id", "subject_type", "subject_id");
create index if not exists "enrollments_user_idx" on "app_private"."enrollments" ("user_id");

create table if not exists "app_private"."enrollment_steps" (
  "enrollment_id" uuid not null references "app_private"."enrollments" ("id") on delete cascade,
  "tenant_id" uuid,
  "step" text not null,
  "completed_by" uuid,
  "completed_at" timestamptz not null default now(),
  primary key ("enrollment_id", "step")
);

alter table "app_private"."enrollment_programs" enable row level security;
revoke all on "app_private"."enrollment_programs" from public, anon, authenticated;
grant select on "app_private"."enrollment_programs" to authenticated;
grant all on "app_private"."enrollment_programs" to service_role;
drop policy if exists "enrollment_programs_read" on "app_private"."enrollment_programs";
create policy enrollment_programs_read on "app_private"."enrollment_programs"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')));
alter table "app_private"."enrollments" enable row level security;
revoke all on "app_private"."enrollments" from public, anon, authenticated;
grant select on "app_private"."enrollments" to authenticated;
grant all on "app_private"."enrollments" to service_role;
drop policy if exists "enrollments_read" on "app_private"."enrollments";
create policy enrollments_read on "app_private"."enrollments"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')));
alter table "app_private"."enrollment_steps" enable row level security;
revoke all on "app_private"."enrollment_steps" from public, anon, authenticated;
grant select on "app_private"."enrollment_steps" to authenticated;
grant all on "app_private"."enrollment_steps" to service_role;
drop policy if exists "enrollment_steps_read" on "app_private"."enrollment_steps";
create policy enrollment_steps_read on "app_private"."enrollment_steps"
  for select to authenticated
  using (exists (select 1 from "app_private"."enrollments" x where x."id" = "app_private"."enrollment_steps"."enrollment_id"));

-- An enrollment with its steps and the completed ones, oldest first.
create or replace function "app_private"."enrollment_json"(enrollment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id", 'organizationId', x."tenant_id", 'program', x."program", 'programVersion', x."program_version",
    'subjectType', x."subject_type", 'subjectId', x."subject_id", 'status', x."status",
    'steps', to_jsonb(x."steps"), 'completedSteps', x."completed_steps", 'totalSteps', cardinality(x."steps"),
    'enrolledBy', x."enrolled_by", 'enrolledAt', x."enrolled_at", 'completedAt', x."completed_at",
    'cancelledAt', x."cancelled_at", 'updatedAt', x."updated_at",
    'progress', coalesce((
      select jsonb_agg(jsonb_build_object('step', y."step", 'completedAt', y."completed_at", 'completedBy', y."completed_by") order by y."completed_at", array_position(x."steps", y."step"), y."step")
      from "app_private"."enrollment_steps" y where y."enrollment_id" = x."id"
    ), '[]'::jsonb)
  )
  from "app_private"."enrollments" x
  where x."id" = enrollment_json.enrollment_id
$$;
revoke execute on function "app_private"."enrollment_json"(uuid) from public, anon, authenticated;

-- The enrollment of a subject in a program, created when missing. steps are
-- the program's step ids; when they changed, the enrollment takes them and
-- recounts. For this module and modules that drive their own programs, such
-- as onboarding (program keys with a colon).
create or replace function "app_private"."enrollment_ensure"(tenant uuid, program text, program_version integer, steps text[], subject_type text, subject_id text, actor uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."enrollments";
begin
  select * into v_row from "app_private"."enrollments" x
  where x."tenant_id" is not distinct from enrollment_ensure.tenant and x."program" = enrollment_ensure.program
    and x."subject_type" = enrollment_ensure.subject_type and x."subject_id" = enrollment_ensure.subject_id
  for update;
  if v_row."id" is null then
    insert into "app_private"."enrollments" ("tenant_id", "program", "program_version", "subject_type", "subject_id", "user_id", "steps", "enrolled_by")
    values (enrollment_ensure.tenant, enrollment_ensure.program, enrollment_ensure.program_version, enrollment_ensure.subject_type, enrollment_ensure.subject_id, case when enrollment_ensure.subject_type = 'user' then enrollment_ensure.subject_id::uuid end, enrollment_ensure.steps, enrollment_ensure.actor)
    on conflict do nothing
    returning * into v_row;
    if v_row."id" is null then
      select * into v_row from "app_private"."enrollments" x
      where x."tenant_id" is not distinct from enrollment_ensure.tenant and x."program" = enrollment_ensure.program
        and x."subject_type" = enrollment_ensure.subject_type and x."subject_id" = enrollment_ensure.subject_id;
      return v_row."id";
    end if;
    return v_row."id";
  end if;
  if v_row."steps" is distinct from enrollment_ensure.steps or v_row."program_version" is distinct from enrollment_ensure.program_version then
    update "app_private"."enrollments" x set "steps" = enrollment_ensure.steps, "program_version" = enrollment_ensure.program_version
    where x."id" = v_row."id";
    update "app_private"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "app_private"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "app_private"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "app_private"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  end if;
  return v_row."id";
end;
$$;
revoke execute on function "app_private"."enrollment_ensure"(uuid, text, integer, text[], text, text, uuid) from public, anon, authenticated;

-- Marks a step done or not done without a permission check; false when it
-- already was. Emits enrollment.step_completed and enrollment.completed for
-- enrollments in an organization.
create or replace function "app_private"."enrollment_mark"(enrollment_id uuid, step text, done boolean, actor uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."enrollments";
  v_was text;
  v_count integer;
begin
  select * into v_row from "app_private"."enrollments" x where x."id" = enrollment_mark.enrollment_id for update;
  if v_row."id" is null then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if enrollment_mark.step is null or not (enrollment_mark.step = any(v_row."steps")) then
    raise exception 'this step is not part of the program' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'cancelled' then
    raise exception 'the enrollment is cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_was := v_row."status";
  if enrollment_mark.done then
    insert into "app_private"."enrollment_steps" ("enrollment_id", "tenant_id", "step", "completed_by")
    values (v_row."id", v_row."tenant_id", enrollment_mark.step, enrollment_mark.actor)
    on conflict do nothing;
  else
    delete from "app_private"."enrollment_steps" x where x."enrollment_id" = v_row."id" and x."step" = enrollment_mark.step;
  end if;
  get diagnostics v_count = row_count;
  if v_count = 0 then
    return false;
  end if;
  update "app_private"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "app_private"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "app_private"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "app_private"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if enrollment_mark.done then
    if v_was <> 'completed' and v_row."status" = 'completed' then
      null;
    end if;
  end if;
  return true;
end;
$$;
revoke execute on function "app_private"."enrollment_mark"(uuid, text, boolean, uuid) from public, anon, authenticated;

-- Creates or changes a program. program is { id?, version?, key, name,
-- description, subjectTypes, steps, enabled }; keys left out keep their value.
-- Changing the steps raises the version. version, when given, must be the
-- stored one.
create or replace function "app_private"."save_enrollment_program"(tenant uuid, program jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "app_private"."enrollment_programs";
  v_row "app_private"."enrollment_programs";
  v_key text;
  v_name text;
  v_description text;
  v_types text[];
  v_steps jsonb;
  v_enabled boolean;
  v_step jsonb;
  v_ids text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_enrollment_program.tenant is not null and coalesce(better_supabase.can('tenant', save_enrollment_program.tenant, 'enrollments.manage'), false))) then
    raise exception 'not allowed to manage enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if save_enrollment_program.program is null or jsonb_typeof(save_enrollment_program.program) <> 'object' then
    raise exception 'program must be an object' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_id := nullif(save_enrollment_program.program ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "app_private"."enrollment_programs" x
    where x."id" = v_id and x."tenant_id" = save_enrollment_program.tenant
    for update;
    if v_old."id" is null then
      raise exception 'enrollment program not found' using errcode = 'P0002', hint = 'ENROLLMENTS_PROGRAM_NOT_FOUND';
    end if;
    if save_enrollment_program.program ? 'version' and (save_enrollment_program.program ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'the program changed since you read it' using errcode = '40001', hint = 'ENROLLMENTS_PROGRAM_CONFLICT';
    end if;
  end if;
  if save_enrollment_program.program ? 'subjectTypes' and jsonb_typeof(save_enrollment_program.program -> 'subjectTypes') <> 'array' then
    raise exception 'subjectTypes must be an array of subject types' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_key := coalesce(save_enrollment_program.program ->> 'key', v_old."key");
  v_name := trim(coalesce(save_enrollment_program.program ->> 'name', v_old."name"));
  v_description := case when save_enrollment_program.program ? 'description'
    then nullif(trim(save_enrollment_program.program ->> 'description'), '') else v_old."description" end;
  v_types := case when save_enrollment_program.program ? 'subjectTypes'
    then array(select t.value from jsonb_array_elements_text(save_enrollment_program.program -> 'subjectTypes') with ordinality as t(value, ord) order by t.ord)
    else coalesce(v_old."subject_types", '{}') end;
  v_steps := case when save_enrollment_program.program ? 'steps'
    then save_enrollment_program.program -> 'steps' else coalesce(v_old."steps", '[]'::jsonb) end;
  v_enabled := case when save_enrollment_program.program ? 'enabled'
    then (save_enrollment_program.program ->> 'enabled')::boolean else coalesce(v_old."enabled", true) end;
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'key: use lowercase letters, digits, "_" or "-", starting with a letter' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_old."id" is not null and v_key <> v_old."key" then
    raise exception 'a program''s key can''t change' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_name is null or length(v_name) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if length(v_description) > 2000 then
    raise exception 'description must be at most 2000 characters' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if exists (select 1 from unnest(v_types) as t(value) where t.value is null or t.value !~ '^[a-z][a-z0-9_-]{0,62}$') then
    raise exception 'subjectTypes must be lower-case subject types' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) = 0 then
    raise exception 'steps: pass at least one step' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if jsonb_array_length(v_steps) > 100 then
    raise exception 'a program holds at most 100 steps' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  for v_step in select t.value from jsonb_array_elements(v_steps) as t(value) loop
    if jsonb_typeof(v_step) <> 'object' or coalesce(v_step ->> 'id', '') !~ '^[a-z][a-z0-9_.-]{0,63}$' then
      raise exception 'each step needs an id of lowercase letters, digits, "_", "." or "-"' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    if (v_step ->> 'id') = any(v_ids) then
      raise exception 'step ids must be unique' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    if length(v_step ->> 'title') > 200 or length(v_step ->> 'description') > 2000 then
      raise exception 'a step title holds at most 200 characters and a description 2000' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    v_ids := v_ids || (v_step ->> 'id');
  end loop;
  v_steps := (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', t.value ->> 'id', 'title', t.value ->> 'title', 'description', t.value ->> 'description')) order by t.ord)
    from jsonb_array_elements(v_steps) with ordinality as t(value, ord)
  );
  if v_old."id" is null then
    insert into "app_private"."enrollment_programs" ("tenant_id", "key", "name", "description", "subject_types", "steps", "enabled", "created_by")
    values (save_enrollment_program.tenant, v_key, v_name, v_description, v_types, v_steps, v_enabled, auth.uid())
    on conflict ("tenant_id", "key") do nothing
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'a program with this key already exists' using errcode = '23505', hint = 'ENROLLMENTS_PROGRAM_EXISTS';
    end if;
  else
    update "app_private"."enrollment_programs" x
    set "name" = v_name, "description" = v_description, "subject_types" = v_types, "steps" = v_steps,
      "enabled" = v_enabled,
      "version" = x."version" + case when x."steps" is distinct from v_steps then 1 else 0 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectTypes', to_jsonb(v_row."subject_types"), 'steps', v_row."steps", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."save_enrollment_program"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_enrollment_program"(uuid, jsonb) to authenticated, service_role;

-- The organization's programs by key.
create or replace function "app_private"."enrollment_programs"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enrollment_programs.tenant is not null and coalesce(better_supabase.can('tenant', enrollment_programs.tenant, 'enrollments.read'), false))) then
    raise exception 'not allowed to read enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectTypes', to_jsonb(x."subject_types"), 'steps', x."steps", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."key")
    from "app_private"."enrollment_programs" x where x."tenant_id" = enrollment_programs.tenant
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."enrollment_programs"(uuid) from public, anon;
grant execute on function "app_private"."enrollment_programs"(uuid) to authenticated, service_role;

-- Deletes a program with its enrollments; false when it was already gone.
create or replace function "app_private"."delete_enrollment_program"(program_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."enrollment_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."enrollment_programs" x where x."id" = delete_enrollment_program.program_id for update;
  if v_row."id" is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.manage'), false))) then
    raise exception 'not allowed to manage enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  delete from "app_private"."enrollments" x where x."tenant_id" = v_row."tenant_id" and x."program" = v_row."key";
  delete from "app_private"."enrollment_programs" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_enrollment_program"(uuid) from public, anon;
grant execute on function "app_private"."delete_enrollment_program"(uuid) to authenticated, service_role;

-- Enrolls a subject in a program; returns the enrollment. Enrolling an
-- enrolled subject returns its enrollment, and enrolling a cancelled one
-- starts it again with its completed steps.
create or replace function "app_private"."enroll"(tenant uuid, program text, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_program "app_private"."enrollment_programs";
  v_row "app_private"."enrollments";
  v_id uuid;
  v_steps text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enroll.tenant is not null and coalesce(better_supabase.can('tenant', enroll.tenant, 'enrollments.enroll'), false))) then
    raise exception 'not allowed to enroll' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  select * into v_program from "app_private"."enrollment_programs" x
  where x."tenant_id" = enroll.tenant and x."key" = enroll.program;
  if v_program."id" is null then
    raise exception 'enrollment program not found' using errcode = 'P0002', hint = 'ENROLLMENTS_PROGRAM_NOT_FOUND';
  end if;
  if not v_program."enabled" then
    raise exception 'this program is turned off' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if enroll.subject_type is null or enroll.subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' or enroll.subject_id is null or length(enroll.subject_id) not between 1 and 200 then
    raise exception 'an enrollment needs a subject type and id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if cardinality(v_program."subject_types") > 0 and not (enroll.subject_type = any(v_program."subject_types")) then
    raise exception 'this program doesn''t enroll this subject type' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if enroll.subject_type = 'user' and enroll.subject_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'a user subject needs a user id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_steps := array(select t.value ->> 'id' from jsonb_array_elements(v_program."steps") with ordinality as t(value, ord) order by t.ord);
  select * into v_row from "app_private"."enrollments" x
  where x."tenant_id" = enroll.tenant and x."program" = enroll.program
    and x."subject_type" = enroll.subject_type and x."subject_id" = enroll.subject_id
  for update;
  if v_row."status" = 'cancelled' then
    update "app_private"."enrollments" x
    set "status" = 'active', "cancelled_at" = null, "enrolled_by" = auth.uid(), "enrolled_at" = now(),
      "steps" = v_steps, "program_version" = v_program."version"
    where x."id" = v_row."id";
    update "app_private"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "app_private"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "app_private"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "app_private"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
    v_id := v_row."id";
  else
    v_id := "app_private"."enrollment_ensure"(enroll.tenant, enroll.program, v_program."version", v_steps, enroll.subject_type, enroll.subject_id, auth.uid());
  end if;
  return "app_private"."enrollment_json"(v_id);
end;
$$;
revoke execute on function "app_private"."enroll"(uuid, text, text, text) from public, anon;
grant execute on function "app_private"."enroll"(uuid, text, text, text) to authenticated, service_role;

-- A subject's enrollment in a program, or null. A user reads their own.
create or replace function "app_private"."enrollment"(tenant uuid, program text, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enrollment.tenant is not null and coalesce(better_supabase.can('tenant', enrollment.tenant, 'enrollments.read'), false))) or (enrollment.subject_type = 'user' and enrollment.subject_id = auth.uid()::text)) then
    raise exception 'not allowed to read enrollments' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  select x."id" into v_id from "app_private"."enrollments" x
  where x."tenant_id" = enrollment.tenant and x."program" = enrollment.program
    and x."subject_type" = enrollment.subject_type and x."subject_id" = enrollment.subject_id;
  return case when v_id is null then null else "app_private"."enrollment_json"(v_id) end;
end;
$$;
revoke execute on function "app_private"."enrollment"(uuid, text, text, text) from public, anon;
grant execute on function "app_private"."enrollment"(uuid, text, text, text) to authenticated, service_role;

-- The organization's enrollments, most recently changed first. Without
-- enrollments.read a member sees only their own.
create or replace function "app_private"."list_enrollments"(tenant uuid, program text default null, subject_type text default null, subject_id text default null, status text default null, page_size integer default null, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_read boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', list_enrollments.tenant, 'enrollments.read'), false)));
begin
  if not v_read and auth.uid() is null then
    raise exception 'not allowed to read enrollments' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if list_enrollments.status is not null and list_enrollments.status not in ('active', 'completed', 'cancelled') then
    raise exception 'status must be active, completed or cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  return coalesce((
    select jsonb_agg("app_private"."enrollment_json"(y."id") order by y."updated_at" desc, y."id")
    from (
      select x."id", x."updated_at" from "app_private"."enrollments" x
      where x."tenant_id" = list_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (list_enrollments.program is null or x."program" = list_enrollments.program)
        and (list_enrollments.subject_type is null or x."subject_type" = list_enrollments.subject_type)
        and (list_enrollments.subject_id is null or x."subject_id" = list_enrollments.subject_id)
        and (list_enrollments.status is null or x."status" = list_enrollments.status)
        and (list_enrollments.before is null or x."updated_at" < list_enrollments.before)
      order by x."updated_at" desc, x."id"
      limit least(greatest(coalesce(list_enrollments.page_size, 50), 1), 200)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."list_enrollments"(uuid, text, text, text, text, integer, timestamptz) from public, anon;
grant execute on function "app_private"."list_enrollments"(uuid, text, text, text, text, integer, timestamptz) to authenticated, service_role;

-- Marks a step of an enrollment done or not done: enrollments.enroll, or the
-- enrolled user for their own.
create or replace function "app_private"."enrollment_step"(enrollment_id uuid, step text, done boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."enrollments";
begin
  select * into v_row from "app_private"."enrollments" x where x."id" = enrollment_step.enrollment_id;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.read'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.enroll'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'not allowed to change this enrollment' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  -- A course's steps follow its lessons, so they change only through courses.
  if v_row."program" like 'course:%' then
    raise exception 'this enrollment belongs to a course; complete its lessons through courses' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  -- A sequence's steps run on its schedule, so only its runner marks them.
  if v_row."program" like 'sequence:%' then
    raise exception 'this enrollment belongs to a sequence; its steps run on the sequence''s schedule' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  perform "app_private"."enrollment_mark"(v_row."id", enrollment_step.step, enrollment_step.done, auth.uid());
  return "app_private"."enrollment_json"(v_row."id");
end;
$$;
revoke execute on function "app_private"."enrollment_step"(uuid, text, boolean) from public, anon, authenticated;

create or replace function "app_private"."complete_enrollment_step"(enrollment_id uuid, step text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "app_private"."enrollment_step"(complete_enrollment_step.enrollment_id, complete_enrollment_step.step, true)
$$;
revoke execute on function "app_private"."complete_enrollment_step"(uuid, text) from public, anon;
grant execute on function "app_private"."complete_enrollment_step"(uuid, text) to authenticated, service_role;

create or replace function "app_private"."reset_enrollment_step"(enrollment_id uuid, step text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "app_private"."enrollment_step"(reset_enrollment_step.enrollment_id, reset_enrollment_step.step, false)
$$;
revoke execute on function "app_private"."reset_enrollment_step"(uuid, text) from public, anon;
grant execute on function "app_private"."reset_enrollment_step"(uuid, text) to authenticated, service_role;

-- Cancels an active enrollment; its completed steps stay. A cancelled one is
-- returned as it is. Programs a module drives can't be cancelled.
create or replace function "app_private"."cancel_enrollment"(enrollment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."enrollments" x where x."id" = cancel_enrollment.enrollment_id for update;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.read'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.enroll'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'not allowed to change this enrollment' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if position(':' in v_row."program") > 0 then
    raise exception 'this enrollment belongs to a module and can''t be cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'completed' then
    raise exception 'a completed enrollment can''t be cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'active' then
    update "app_private"."enrollments" x
    set "status" = 'cancelled', "cancelled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  return "app_private"."enrollment_json"(v_row."id");
end;
$$;
revoke execute on function "app_private"."cancel_enrollment"(uuid) from public, anon;
grant execute on function "app_private"."cancel_enrollment"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."enrollment_programs";
drop policy if exists bsb_tenant_scope_select on "app_private"."enrollment_programs";
create policy bsb_tenant_scope_select on "app_private"."enrollment_programs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."enrollment_programs";
create policy bsb_tenant_scope_insert on "app_private"."enrollment_programs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."enrollment_programs";
create policy bsb_tenant_scope_update on "app_private"."enrollment_programs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."enrollment_programs";
create policy bsb_tenant_scope_delete on "app_private"."enrollment_programs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."enrollments";
drop policy if exists bsb_tenant_scope_select on "app_private"."enrollments";
create policy bsb_tenant_scope_select on "app_private"."enrollments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."enrollments";
create policy bsb_tenant_scope_insert on "app_private"."enrollments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."enrollments";
create policy bsb_tenant_scope_update on "app_private"."enrollments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."enrollments";
create policy bsb_tenant_scope_delete on "app_private"."enrollments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."enrollment_steps";
drop policy if exists bsb_tenant_scope_select on "app_private"."enrollment_steps";
create policy bsb_tenant_scope_select on "app_private"."enrollment_steps" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "app_private"."enrollments" x where x."id" = "app_private"."enrollment_steps"."enrollment_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."enrollment_steps";
create policy bsb_tenant_scope_insert on "app_private"."enrollment_steps" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."enrollment_steps";
create policy bsb_tenant_scope_update on "app_private"."enrollment_steps" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."enrollment_steps";
create policy bsb_tenant_scope_delete on "app_private"."enrollment_steps" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_036_enrollments.sql
-- better-supabase module: enrollments
-- @bsb-block-data enrollments
-- @bsb-hash sha256:ba27786140fd499c4d1e2ab814ef20ead1970f014ec0279b82377d83afb2017a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('enrollments', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_036_enrollments.sql
-- better-supabase module: enrollments
-- @bsb-block enrollments@1 managed
-- @bsb-hash sha256:e57134f08600d2d6ff6cf1f1ea058c9b43dc72cc61fa8d20dadbc30171a7e2e2
-- Programs of steps per organization, and enrollments of a party, a member or any subject in them with step progress and completion. Onboarding checklists run on it.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_programs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_steps";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."enrollment_programs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  -- The subject types it enrolls; empty enrolls any.
  "subject_types" text[] not null default '{}',
  -- [{ id, title, description }], in order.
  "steps" jsonb not null default '[]'::jsonb check (jsonb_typeof("steps") = 'array'),
  "enabled" boolean not null default true,
  "version" integer not null default 1,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);

-- One per program and subject. A user's own onboarding checklist has no
-- tenant; user_id is set for user subjects so the row goes with the user.
create table if not exists "better_supabase"."enrollments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "program" text not null check (length("program") between 1 and 200),
  "program_version" integer,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "user_id" uuid references auth.users (id) on delete cascade,
  -- The program's step ids when it enrolled or last changed.
  "steps" text[] not null default '{}',
  "completed_steps" integer not null default 0 check ("completed_steps" >= 0),
  "status" text not null default 'active' check ("status" in ('active', 'completed', 'cancelled')),
  "enrolled_by" uuid,
  "enrolled_at" timestamptz not null default now(),
  "completed_at" timestamptz,
  "cancelled_at" timestamptz,
  "updated_at" timestamptz not null default now(),
  check (("subject_type" = 'user') = ("user_id" is not null)),
  check ("user_id" is null or "subject_id" = "user_id"::text),
  unique nulls not distinct ("tenant_id", "program", "subject_type", "subject_id")
);
create index if not exists "enrollments_program_idx" on "better_supabase"."enrollments" ("tenant_id", "program", "status");
create index if not exists "enrollments_subject_idx" on "better_supabase"."enrollments" ("tenant_id", "subject_type", "subject_id");
create index if not exists "enrollments_user_idx" on "better_supabase"."enrollments" ("user_id");

create table if not exists "better_supabase"."enrollment_steps" (
  "enrollment_id" uuid not null references "better_supabase"."enrollments" ("id") on delete cascade,
  "tenant_id" uuid,
  "step" text not null,
  "completed_by" uuid,
  "completed_at" timestamptz not null default now(),
  primary key ("enrollment_id", "step")
);

alter table "better_supabase"."enrollment_programs" enable row level security;
revoke all on "better_supabase"."enrollment_programs" from public, anon, authenticated;
grant select on "better_supabase"."enrollment_programs" to authenticated;
grant all on "better_supabase"."enrollment_programs" to service_role;
drop policy if exists "enrollment_programs_read" on "better_supabase"."enrollment_programs";
create policy enrollment_programs_read on "better_supabase"."enrollment_programs"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')));
alter table "better_supabase"."enrollments" enable row level security;
revoke all on "better_supabase"."enrollments" from public, anon, authenticated;
grant select on "better_supabase"."enrollments" to authenticated;
grant all on "better_supabase"."enrollments" to service_role;
drop policy if exists "enrollments_read" on "better_supabase"."enrollments";
create policy enrollments_read on "better_supabase"."enrollments"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')));
alter table "better_supabase"."enrollment_steps" enable row level security;
revoke all on "better_supabase"."enrollment_steps" from public, anon, authenticated;
grant select on "better_supabase"."enrollment_steps" to authenticated;
grant all on "better_supabase"."enrollment_steps" to service_role;
drop policy if exists "enrollment_steps_read" on "better_supabase"."enrollment_steps";
create policy enrollment_steps_read on "better_supabase"."enrollment_steps"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."enrollments" x where x."id" = "better_supabase"."enrollment_steps"."enrollment_id"));

-- An enrollment with its steps and the completed ones, oldest first.
create or replace function "better_supabase"."enrollment_json"(enrollment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id", 'organizationId', x."tenant_id", 'program', x."program", 'programVersion', x."program_version",
    'subjectType', x."subject_type", 'subjectId', x."subject_id", 'status', x."status",
    'steps', to_jsonb(x."steps"), 'completedSteps', x."completed_steps", 'totalSteps', cardinality(x."steps"),
    'enrolledBy', x."enrolled_by", 'enrolledAt', x."enrolled_at", 'completedAt', x."completed_at",
    'cancelledAt', x."cancelled_at", 'updatedAt', x."updated_at",
    'progress', coalesce((
      select jsonb_agg(jsonb_build_object('step', y."step", 'completedAt', y."completed_at", 'completedBy', y."completed_by") order by y."completed_at", array_position(x."steps", y."step"), y."step")
      from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id"
    ), '[]'::jsonb)
  )
  from "better_supabase"."enrollments" x
  where x."id" = enrollment_json.enrollment_id
$$;
revoke execute on function "better_supabase"."enrollment_json"(uuid) from public, anon, authenticated;

-- The enrollment of a subject in a program, created when missing. steps are
-- the program's step ids; when they changed, the enrollment takes them and
-- recounts. For this module and modules that drive their own programs, such
-- as onboarding (program keys with a colon).
create or replace function "better_supabase"."enrollment_ensure"(tenant uuid, program text, program_version integer, steps text[], subject_type text, subject_id text, actor uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."enrollments";
begin
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" is not distinct from enrollment_ensure.tenant and x."program" = enrollment_ensure.program
    and x."subject_type" = enrollment_ensure.subject_type and x."subject_id" = enrollment_ensure.subject_id
  for update;
  if v_row."id" is null then
    insert into "better_supabase"."enrollments" ("tenant_id", "program", "program_version", "subject_type", "subject_id", "user_id", "steps", "enrolled_by")
    values (enrollment_ensure.tenant, enrollment_ensure.program, enrollment_ensure.program_version, enrollment_ensure.subject_type, enrollment_ensure.subject_id, case when enrollment_ensure.subject_type = 'user' then enrollment_ensure.subject_id::uuid end, enrollment_ensure.steps, enrollment_ensure.actor)
    on conflict do nothing
    returning * into v_row;
    if v_row."id" is null then
      select * into v_row from "better_supabase"."enrollments" x
      where x."tenant_id" is not distinct from enrollment_ensure.tenant and x."program" = enrollment_ensure.program
        and x."subject_type" = enrollment_ensure.subject_type and x."subject_id" = enrollment_ensure.subject_id;
      return v_row."id";
    end if;
    return v_row."id";
  end if;
  if v_row."steps" is distinct from enrollment_ensure.steps or v_row."program_version" is distinct from enrollment_ensure.program_version then
    update "better_supabase"."enrollments" x set "steps" = enrollment_ensure.steps, "program_version" = enrollment_ensure.program_version
    where x."id" = v_row."id";
    update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  end if;
  return v_row."id";
end;
$$;
revoke execute on function "better_supabase"."enrollment_ensure"(uuid, text, integer, text[], text, text, uuid) from public, anon, authenticated;

-- Marks a step done or not done without a permission check; false when it
-- already was. Emits enrollment.step_completed and enrollment.completed for
-- enrollments in an organization.
create or replace function "better_supabase"."enrollment_mark"(enrollment_id uuid, step text, done boolean, actor uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."enrollments";
  v_was text;
  v_count integer;
begin
  select * into v_row from "better_supabase"."enrollments" x where x."id" = enrollment_mark.enrollment_id for update;
  if v_row."id" is null then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if enrollment_mark.step is null or not (enrollment_mark.step = any(v_row."steps")) then
    raise exception 'this step is not part of the program' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'cancelled' then
    raise exception 'the enrollment is cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_was := v_row."status";
  if enrollment_mark.done then
    insert into "better_supabase"."enrollment_steps" ("enrollment_id", "tenant_id", "step", "completed_by")
    values (v_row."id", v_row."tenant_id", enrollment_mark.step, enrollment_mark.actor)
    on conflict do nothing;
  else
    delete from "better_supabase"."enrollment_steps" x where x."enrollment_id" = v_row."id" and x."step" = enrollment_mark.step;
  end if;
  get diagnostics v_count = row_count;
  if v_count = 0 then
    return false;
  end if;
  update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if enrollment_mark.done then
    if v_was <> 'completed' and v_row."status" = 'completed' then
      null;
    end if;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."enrollment_mark"(uuid, text, boolean, uuid) from public, anon, authenticated;

-- Creates or changes a program. program is { id?, version?, key, name,
-- description, subjectTypes, steps, enabled }; keys left out keep their value.
-- Changing the steps raises the version. version, when given, must be the
-- stored one.
create or replace function "better_supabase"."save_enrollment_program"(tenant uuid, program jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."enrollment_programs";
  v_row "better_supabase"."enrollment_programs";
  v_key text;
  v_name text;
  v_description text;
  v_types text[];
  v_steps jsonb;
  v_enabled boolean;
  v_step jsonb;
  v_ids text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_enrollment_program.tenant is not null and coalesce(better_supabase.can('tenant', save_enrollment_program.tenant, 'enrollments.manage'), false))) then
    raise exception 'not allowed to manage enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if save_enrollment_program.program is null or jsonb_typeof(save_enrollment_program.program) <> 'object' then
    raise exception 'program must be an object' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_id := nullif(save_enrollment_program.program ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."enrollment_programs" x
    where x."id" = v_id and x."tenant_id" = save_enrollment_program.tenant
    for update;
    if v_old."id" is null then
      raise exception 'enrollment program not found' using errcode = 'P0002', hint = 'ENROLLMENTS_PROGRAM_NOT_FOUND';
    end if;
    if save_enrollment_program.program ? 'version' and (save_enrollment_program.program ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'the program changed since you read it' using errcode = '40001', hint = 'ENROLLMENTS_PROGRAM_CONFLICT';
    end if;
  end if;
  if save_enrollment_program.program ? 'subjectTypes' and jsonb_typeof(save_enrollment_program.program -> 'subjectTypes') <> 'array' then
    raise exception 'subjectTypes must be an array of subject types' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_key := coalesce(save_enrollment_program.program ->> 'key', v_old."key");
  v_name := trim(coalesce(save_enrollment_program.program ->> 'name', v_old."name"));
  v_description := case when save_enrollment_program.program ? 'description'
    then nullif(trim(save_enrollment_program.program ->> 'description'), '') else v_old."description" end;
  v_types := case when save_enrollment_program.program ? 'subjectTypes'
    then array(select t.value from jsonb_array_elements_text(save_enrollment_program.program -> 'subjectTypes') with ordinality as t(value, ord) order by t.ord)
    else coalesce(v_old."subject_types", '{}') end;
  v_steps := case when save_enrollment_program.program ? 'steps'
    then save_enrollment_program.program -> 'steps' else coalesce(v_old."steps", '[]'::jsonb) end;
  v_enabled := case when save_enrollment_program.program ? 'enabled'
    then (save_enrollment_program.program ->> 'enabled')::boolean else coalesce(v_old."enabled", true) end;
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'key: use lowercase letters, digits, "_" or "-", starting with a letter' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_old."id" is not null and v_key <> v_old."key" then
    raise exception 'a program''s key can''t change' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_name is null or length(v_name) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if length(v_description) > 2000 then
    raise exception 'description must be at most 2000 characters' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if exists (select 1 from unnest(v_types) as t(value) where t.value is null or t.value !~ '^[a-z][a-z0-9_-]{0,62}$') then
    raise exception 'subjectTypes must be lower-case subject types' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) = 0 then
    raise exception 'steps: pass at least one step' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if jsonb_array_length(v_steps) > 100 then
    raise exception 'a program holds at most 100 steps' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  for v_step in select t.value from jsonb_array_elements(v_steps) as t(value) loop
    if jsonb_typeof(v_step) <> 'object' or coalesce(v_step ->> 'id', '') !~ '^[a-z][a-z0-9_.-]{0,63}$' then
      raise exception 'each step needs an id of lowercase letters, digits, "_", "." or "-"' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    if (v_step ->> 'id') = any(v_ids) then
      raise exception 'step ids must be unique' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    if length(v_step ->> 'title') > 200 or length(v_step ->> 'description') > 2000 then
      raise exception 'a step title holds at most 200 characters and a description 2000' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    v_ids := v_ids || (v_step ->> 'id');
  end loop;
  v_steps := (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', t.value ->> 'id', 'title', t.value ->> 'title', 'description', t.value ->> 'description')) order by t.ord)
    from jsonb_array_elements(v_steps) with ordinality as t(value, ord)
  );
  if v_old."id" is null then
    insert into "better_supabase"."enrollment_programs" ("tenant_id", "key", "name", "description", "subject_types", "steps", "enabled", "created_by")
    values (save_enrollment_program.tenant, v_key, v_name, v_description, v_types, v_steps, v_enabled, auth.uid())
    on conflict ("tenant_id", "key") do nothing
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'a program with this key already exists' using errcode = '23505', hint = 'ENROLLMENTS_PROGRAM_EXISTS';
    end if;
  else
    update "better_supabase"."enrollment_programs" x
    set "name" = v_name, "description" = v_description, "subject_types" = v_types, "steps" = v_steps,
      "enabled" = v_enabled,
      "version" = x."version" + case when x."steps" is distinct from v_steps then 1 else 0 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectTypes', to_jsonb(v_row."subject_types"), 'steps', v_row."steps", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_enrollment_program"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_enrollment_program"(uuid, jsonb) to authenticated, service_role;

-- The organization's programs by key.
create or replace function "better_supabase"."enrollment_programs"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enrollment_programs.tenant is not null and coalesce(better_supabase.can('tenant', enrollment_programs.tenant, 'enrollments.read'), false))) then
    raise exception 'not allowed to read enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectTypes', to_jsonb(x."subject_types"), 'steps', x."steps", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."key")
    from "better_supabase"."enrollment_programs" x where x."tenant_id" = enrollment_programs.tenant
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."enrollment_programs"(uuid) from public, anon;
grant execute on function "better_supabase"."enrollment_programs"(uuid) to authenticated, service_role;

-- Deletes a program with its enrollments; false when it was already gone.
create or replace function "better_supabase"."delete_enrollment_program"(program_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."enrollment_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."enrollment_programs" x where x."id" = delete_enrollment_program.program_id for update;
  if v_row."id" is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.manage'), false))) then
    raise exception 'not allowed to manage enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  delete from "better_supabase"."enrollments" x where x."tenant_id" = v_row."tenant_id" and x."program" = v_row."key";
  delete from "better_supabase"."enrollment_programs" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_enrollment_program"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_enrollment_program"(uuid) to authenticated, service_role;

-- Enrolls a subject in a program; returns the enrollment. Enrolling an
-- enrolled subject returns its enrollment, and enrolling a cancelled one
-- starts it again with its completed steps.
create or replace function "better_supabase"."enroll"(tenant uuid, program text, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_program "better_supabase"."enrollment_programs";
  v_row "better_supabase"."enrollments";
  v_id uuid;
  v_steps text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enroll.tenant is not null and coalesce(better_supabase.can('tenant', enroll.tenant, 'enrollments.enroll'), false))) then
    raise exception 'not allowed to enroll' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  select * into v_program from "better_supabase"."enrollment_programs" x
  where x."tenant_id" = enroll.tenant and x."key" = enroll.program;
  if v_program."id" is null then
    raise exception 'enrollment program not found' using errcode = 'P0002', hint = 'ENROLLMENTS_PROGRAM_NOT_FOUND';
  end if;
  if not v_program."enabled" then
    raise exception 'this program is turned off' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if enroll.subject_type is null or enroll.subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' or enroll.subject_id is null or length(enroll.subject_id) not between 1 and 200 then
    raise exception 'an enrollment needs a subject type and id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if cardinality(v_program."subject_types") > 0 and not (enroll.subject_type = any(v_program."subject_types")) then
    raise exception 'this program doesn''t enroll this subject type' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if enroll.subject_type = 'user' and enroll.subject_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'a user subject needs a user id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_steps := array(select t.value ->> 'id' from jsonb_array_elements(v_program."steps") with ordinality as t(value, ord) order by t.ord);
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = enroll.tenant and x."program" = enroll.program
    and x."subject_type" = enroll.subject_type and x."subject_id" = enroll.subject_id
  for update;
  if v_row."status" = 'cancelled' then
    update "better_supabase"."enrollments" x
    set "status" = 'active', "cancelled_at" = null, "enrolled_by" = auth.uid(), "enrolled_at" = now(),
      "steps" = v_steps, "program_version" = v_program."version"
    where x."id" = v_row."id";
    update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
    v_id := v_row."id";
  else
    v_id := "better_supabase"."enrollment_ensure"(enroll.tenant, enroll.program, v_program."version", v_steps, enroll.subject_type, enroll.subject_id, auth.uid());
  end if;
  return "better_supabase"."enrollment_json"(v_id);
end;
$$;
revoke execute on function "better_supabase"."enroll"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."enroll"(uuid, text, text, text) to authenticated, service_role;

-- A subject's enrollment in a program, or null. A user reads their own.
create or replace function "better_supabase"."enrollment"(tenant uuid, program text, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enrollment.tenant is not null and coalesce(better_supabase.can('tenant', enrollment.tenant, 'enrollments.read'), false))) or (enrollment.subject_type = 'user' and enrollment.subject_id = auth.uid()::text)) then
    raise exception 'not allowed to read enrollments' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  select x."id" into v_id from "better_supabase"."enrollments" x
  where x."tenant_id" = enrollment.tenant and x."program" = enrollment.program
    and x."subject_type" = enrollment.subject_type and x."subject_id" = enrollment.subject_id;
  return case when v_id is null then null else "better_supabase"."enrollment_json"(v_id) end;
end;
$$;
revoke execute on function "better_supabase"."enrollment"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."enrollment"(uuid, text, text, text) to authenticated, service_role;

-- The organization's enrollments, most recently changed first. Without
-- enrollments.read a member sees only their own.
create or replace function "better_supabase"."list_enrollments"(tenant uuid, program text default null, subject_type text default null, subject_id text default null, status text default null, page_size integer default null, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_read boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', list_enrollments.tenant, 'enrollments.read'), false)));
begin
  if not v_read and auth.uid() is null then
    raise exception 'not allowed to read enrollments' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if list_enrollments.status is not null and list_enrollments.status not in ('active', 'completed', 'cancelled') then
    raise exception 'status must be active, completed or cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  return coalesce((
    select jsonb_agg("better_supabase"."enrollment_json"(y."id") order by y."updated_at" desc, y."id")
    from (
      select x."id", x."updated_at" from "better_supabase"."enrollments" x
      where x."tenant_id" = list_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (list_enrollments.program is null or x."program" = list_enrollments.program)
        and (list_enrollments.subject_type is null or x."subject_type" = list_enrollments.subject_type)
        and (list_enrollments.subject_id is null or x."subject_id" = list_enrollments.subject_id)
        and (list_enrollments.status is null or x."status" = list_enrollments.status)
        and (list_enrollments.before is null or x."updated_at" < list_enrollments.before)
      order by x."updated_at" desc, x."id"
      limit least(greatest(coalesce(list_enrollments.page_size, 50), 1), 200)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_enrollments"(uuid, text, text, text, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_enrollments"(uuid, text, text, text, text, integer, timestamptz) to authenticated, service_role;

-- Marks a step of an enrollment done or not done: enrollments.enroll, or the
-- enrolled user for their own.
create or replace function "better_supabase"."enrollment_step"(enrollment_id uuid, step text, done boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."enrollments";
begin
  select * into v_row from "better_supabase"."enrollments" x where x."id" = enrollment_step.enrollment_id;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.read'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.enroll'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'not allowed to change this enrollment' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  -- A course's steps follow its lessons, so they change only through courses.
  if v_row."program" like 'course:%' then
    raise exception 'this enrollment belongs to a course; complete its lessons through courses' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  -- A sequence's steps run on its schedule, so only its runner marks them.
  if v_row."program" like 'sequence:%' then
    raise exception 'this enrollment belongs to a sequence; its steps run on the sequence''s schedule' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  perform "better_supabase"."enrollment_mark"(v_row."id", enrollment_step.step, enrollment_step.done, auth.uid());
  return "better_supabase"."enrollment_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."enrollment_step"(uuid, text, boolean) from public, anon, authenticated;

create or replace function "better_supabase"."complete_enrollment_step"(enrollment_id uuid, step text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."enrollment_step"(complete_enrollment_step.enrollment_id, complete_enrollment_step.step, true)
$$;
revoke execute on function "better_supabase"."complete_enrollment_step"(uuid, text) from public, anon;
grant execute on function "better_supabase"."complete_enrollment_step"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."reset_enrollment_step"(enrollment_id uuid, step text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."enrollment_step"(reset_enrollment_step.enrollment_id, reset_enrollment_step.step, false)
$$;
revoke execute on function "better_supabase"."reset_enrollment_step"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reset_enrollment_step"(uuid, text) to authenticated, service_role;

-- Cancels an active enrollment; its completed steps stay. A cancelled one is
-- returned as it is. Programs a module drives can't be cancelled.
create or replace function "better_supabase"."cancel_enrollment"(enrollment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."enrollments" x where x."id" = cancel_enrollment.enrollment_id for update;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.read'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.enroll'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'not allowed to change this enrollment' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if position(':' in v_row."program") > 0 then
    raise exception 'this enrollment belongs to a module and can''t be cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'completed' then
    raise exception 'a completed enrollment can''t be cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'active' then
    update "better_supabase"."enrollments" x
    set "status" = 'cancelled', "cancelled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  return "better_supabase"."enrollment_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."cancel_enrollment"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_enrollment"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_programs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_select on "better_supabase"."enrollment_programs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_insert on "better_supabase"."enrollment_programs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_update on "better_supabase"."enrollment_programs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_delete on "better_supabase"."enrollment_programs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."enrollments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollments";
create policy bsb_tenant_scope_select on "better_supabase"."enrollments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollments";
create policy bsb_tenant_scope_insert on "better_supabase"."enrollments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollments";
create policy bsb_tenant_scope_update on "better_supabase"."enrollments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollments";
create policy bsb_tenant_scope_delete on "better_supabase"."enrollments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_steps";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_select on "better_supabase"."enrollment_steps" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."enrollments" x where x."id" = "better_supabase"."enrollment_steps"."enrollment_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_insert on "better_supabase"."enrollment_steps" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_update on "better_supabase"."enrollment_steps" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_delete on "better_supabase"."enrollment_steps" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.enrollments.api: entry points for the Data API.
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

create or replace function "api"."save_enrollment_program"(tenant uuid, program jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_enrollment_program"($1, $2) $$;
revoke execute on function "api"."save_enrollment_program"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_enrollment_program"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."enrollment_programs"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."enrollment_programs"($1) $$;
revoke execute on function "api"."enrollment_programs"(uuid) from public, anon;
grant execute on function "api"."enrollment_programs"(uuid) to authenticated, service_role;

create or replace function "api"."delete_enrollment_program"(program_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_enrollment_program"($1) $$;
revoke execute on function "api"."delete_enrollment_program"(uuid) from public, anon;
grant execute on function "api"."delete_enrollment_program"(uuid) to authenticated, service_role;

create or replace function "api"."enroll"(tenant uuid, program text, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."enroll"($1, $2, $3, $4) $$;
revoke execute on function "api"."enroll"(uuid, text, text, text) from public, anon;
grant execute on function "api"."enroll"(uuid, text, text, text) to authenticated, service_role;

create or replace function "api"."enrollment"(tenant uuid, program text, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."enrollment"($1, $2, $3, $4) $$;
revoke execute on function "api"."enrollment"(uuid, text, text, text) from public, anon;
grant execute on function "api"."enrollment"(uuid, text, text, text) to authenticated, service_role;

create or replace function "api"."list_enrollments"(tenant uuid, program text default null, subject_type text default null, subject_id text default null, status text default null, page_size integer default null, before timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_enrollments"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."list_enrollments"(uuid, text, text, text, text, integer, timestamptz) from public, anon;
grant execute on function "api"."list_enrollments"(uuid, text, text, text, text, integer, timestamptz) to authenticated, service_role;

create or replace function "api"."complete_enrollment_step"(enrollment_id uuid, step text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_enrollment_step"($1, $2) $$;
revoke execute on function "api"."complete_enrollment_step"(uuid, text) from public, anon;
grant execute on function "api"."complete_enrollment_step"(uuid, text) to authenticated, service_role;

create or replace function "api"."reset_enrollment_step"(enrollment_id uuid, step text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reset_enrollment_step"($1, $2) $$;
revoke execute on function "api"."reset_enrollment_step"(uuid, text) from public, anon;
grant execute on function "api"."reset_enrollment_step"(uuid, text) to authenticated, service_role;

create or replace function "api"."cancel_enrollment"(enrollment_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_enrollment"($1) $$;
revoke execute on function "api"."cancel_enrollment"(uuid) from public, anon;
grant execute on function "api"."cancel_enrollment"(uuid) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_036_enrollments.sql
-- better-supabase module: enrollments
-- @bsb-block-data enrollments
-- @bsb-hash sha256:ba27786140fd499c4d1e2ab814ef20ead1970f014ec0279b82377d83afb2017a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('enrollments', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_036_enrollments.sql
-- better-supabase module: enrollments
-- @bsb-block enrollments@1 managed
-- @bsb-hash sha256:095d31e88bcb5a3ff17d82cfc36aa88174a77c45c8bdd0b6ccfcd59ab82b671a
-- Programs of steps per organization, and enrollments of a party, a member or any subject in them with step progress and completion. Onboarding checklists run on it.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_programs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_steps";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- better_supabase.enrollment_programs is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."enrollment_programs" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."enrollment_programs" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."enrollment_programs" add column if not exists "key" text check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$');
alter table "better_supabase"."enrollment_programs" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."enrollment_programs" add column if not exists "description" text check ("description" is null or length("description") <= 2000);
alter table "better_supabase"."enrollment_programs" add column if not exists "subject_types" text[] not null default '{}';
alter table "better_supabase"."enrollment_programs" add column if not exists "steps" jsonb not null default '[]'::jsonb check (jsonb_typeof("steps") = 'array');
alter table "better_supabase"."enrollment_programs" add column if not exists "enabled" boolean not null default true;
alter table "better_supabase"."enrollment_programs" add column if not exists "version" integer not null default 1;
alter table "better_supabase"."enrollment_programs" add column if not exists "created_by" uuid;
alter table "better_supabase"."enrollment_programs" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."enrollment_programs" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_enrollment_programs_key_key" on "better_supabase"."enrollment_programs" ("tenant_id", "key");

-- One per program and subject. A user's own onboarding checklist has no
-- tenant; user_id is set for user subjects so the row goes with the user.
-- better_supabase.enrollments is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."enrollments" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."enrollments" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."enrollments" add column if not exists "program" text check (length("program") between 1 and 200);
alter table "better_supabase"."enrollments" add column if not exists "program_version" integer;
alter table "better_supabase"."enrollments" add column if not exists "subject_type" text check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$');
alter table "better_supabase"."enrollments" add column if not exists "subject_id" text check (length("subject_id") between 1 and 200);
alter table "better_supabase"."enrollments" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."enrollments" add column if not exists "steps" text[] not null default '{}';
alter table "better_supabase"."enrollments" add column if not exists "completed_steps" integer not null default 0 check ("completed_steps" >= 0);
alter table "better_supabase"."enrollments" add column if not exists "status" text not null default 'active' check ("status" in ('active', 'completed', 'cancelled'));
alter table "better_supabase"."enrollments" add column if not exists "enrolled_by" uuid;
alter table "better_supabase"."enrollments" add column if not exists "enrolled_at" timestamptz not null default now();
alter table "better_supabase"."enrollments" add column if not exists "completed_at" timestamptz;
alter table "better_supabase"."enrollments" add column if not exists "cancelled_at" timestamptz;
alter table "better_supabase"."enrollments" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_enrollments_subject_key" on "better_supabase"."enrollments" ("tenant_id", "program", "subject_type", "subject_id") nulls not distinct;
create index if not exists "enrollments_program_idx" on "better_supabase"."enrollments" ("tenant_id", "program", "status");
create index if not exists "enrollments_subject_idx" on "better_supabase"."enrollments" ("tenant_id", "subject_type", "subject_id");
create index if not exists "enrollments_user_idx" on "better_supabase"."enrollments" ("user_id");

-- better_supabase.enrollment_steps is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."enrollment_steps" add column if not exists "enrollment_id" uuid references "better_supabase"."enrollments" ("id") on delete cascade;
alter table "better_supabase"."enrollment_steps" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."enrollment_steps" add column if not exists "step" text;
alter table "better_supabase"."enrollment_steps" add column if not exists "completed_by" uuid;
alter table "better_supabase"."enrollment_steps" add column if not exists "completed_at" timestamptz not null default now();
create unique index if not exists "bsb_enrollment_steps_step_key" on "better_supabase"."enrollment_steps" ("enrollment_id", "step");

alter table "better_supabase"."enrollment_programs" enable row level security;
grant select on "better_supabase"."enrollment_programs" to authenticated;
grant all on "better_supabase"."enrollment_programs" to service_role;
drop policy if exists bsb_enrollment_programs_select on "better_supabase"."enrollment_programs";
create policy bsb_enrollment_programs_select on "better_supabase"."enrollment_programs"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')));
alter table "better_supabase"."enrollments" enable row level security;
grant select on "better_supabase"."enrollments" to authenticated;
grant all on "better_supabase"."enrollments" to service_role;
drop policy if exists bsb_enrollments_select on "better_supabase"."enrollments";
create policy bsb_enrollments_select on "better_supabase"."enrollments"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')));
alter table "better_supabase"."enrollment_steps" enable row level security;
grant select on "better_supabase"."enrollment_steps" to authenticated;
grant all on "better_supabase"."enrollment_steps" to service_role;
drop policy if exists bsb_enrollment_steps_select on "better_supabase"."enrollment_steps";
create policy bsb_enrollment_steps_select on "better_supabase"."enrollment_steps"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."enrollments" x where x."id" = "better_supabase"."enrollment_steps"."enrollment_id"));

-- An enrollment with its steps and the completed ones, oldest first.
create or replace function "better_supabase"."enrollment_json"(enrollment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id", 'organizationId', x."tenant_id", 'program', x."program", 'programVersion', x."program_version",
    'subjectType', x."subject_type", 'subjectId', x."subject_id", 'status', x."status",
    'steps', to_jsonb(x."steps"), 'completedSteps', x."completed_steps", 'totalSteps', cardinality(x."steps"),
    'enrolledBy', x."enrolled_by", 'enrolledAt', x."enrolled_at", 'completedAt', x."completed_at",
    'cancelledAt', x."cancelled_at", 'updatedAt', x."updated_at",
    'progress', coalesce((
      select jsonb_agg(jsonb_build_object('step', y."step", 'completedAt', y."completed_at", 'completedBy', y."completed_by") order by y."completed_at", array_position(x."steps", y."step"), y."step")
      from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id"
    ), '[]'::jsonb)
  )
  from "better_supabase"."enrollments" x
  where x."id" = enrollment_json.enrollment_id
$$;
revoke execute on function "better_supabase"."enrollment_json"(uuid) from public, anon, authenticated;

-- The enrollment of a subject in a program, created when missing. steps are
-- the program's step ids; when they changed, the enrollment takes them and
-- recounts. For this module and modules that drive their own programs, such
-- as onboarding (program keys with a colon).
create or replace function "better_supabase"."enrollment_ensure"(tenant uuid, program text, program_version integer, steps text[], subject_type text, subject_id text, actor uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."enrollments";
begin
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" is not distinct from enrollment_ensure.tenant and x."program" = enrollment_ensure.program
    and x."subject_type" = enrollment_ensure.subject_type and x."subject_id" = enrollment_ensure.subject_id
  for update;
  if v_row."id" is null then
    insert into "better_supabase"."enrollments" ("tenant_id", "program", "program_version", "subject_type", "subject_id", "user_id", "steps", "enrolled_by")
    values (enrollment_ensure.tenant, enrollment_ensure.program, enrollment_ensure.program_version, enrollment_ensure.subject_type, enrollment_ensure.subject_id, case when enrollment_ensure.subject_type = 'user' then enrollment_ensure.subject_id::uuid end, enrollment_ensure.steps, enrollment_ensure.actor)
    on conflict do nothing
    returning * into v_row;
    if v_row."id" is null then
      select * into v_row from "better_supabase"."enrollments" x
      where x."tenant_id" is not distinct from enrollment_ensure.tenant and x."program" = enrollment_ensure.program
        and x."subject_type" = enrollment_ensure.subject_type and x."subject_id" = enrollment_ensure.subject_id;
      return v_row."id";
    end if;
    return v_row."id";
  end if;
  if v_row."steps" is distinct from enrollment_ensure.steps or v_row."program_version" is distinct from enrollment_ensure.program_version then
    update "better_supabase"."enrollments" x set "steps" = enrollment_ensure.steps, "program_version" = enrollment_ensure.program_version
    where x."id" = v_row."id";
    update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = better_supabase.as_column_type(case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end, (null::"better_supabase"."enrollments")."status"),
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  end if;
  return v_row."id";
end;
$$;
revoke execute on function "better_supabase"."enrollment_ensure"(uuid, text, integer, text[], text, text, uuid) from public, anon, authenticated;

-- Marks a step done or not done without a permission check; false when it
-- already was. Emits enrollment.step_completed and enrollment.completed for
-- enrollments in an organization.
create or replace function "better_supabase"."enrollment_mark"(enrollment_id uuid, step text, done boolean, actor uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."enrollments";
  v_was text;
  v_count integer;
begin
  select * into v_row from "better_supabase"."enrollments" x where x."id" = enrollment_mark.enrollment_id for update;
  if v_row."id" is null then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if enrollment_mark.step is null or not (enrollment_mark.step = any(v_row."steps")) then
    raise exception 'this step is not part of the program' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'cancelled' then
    raise exception 'the enrollment is cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_was := v_row."status";
  if enrollment_mark.done then
    insert into "better_supabase"."enrollment_steps" ("enrollment_id", "tenant_id", "step", "completed_by")
    values (v_row."id", v_row."tenant_id", enrollment_mark.step, enrollment_mark.actor)
    on conflict do nothing;
  else
    delete from "better_supabase"."enrollment_steps" x where x."enrollment_id" = v_row."id" and x."step" = enrollment_mark.step;
  end if;
  get diagnostics v_count = row_count;
  if v_count = 0 then
    return false;
  end if;
  update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = better_supabase.as_column_type(case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end, (null::"better_supabase"."enrollments")."status"),
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if enrollment_mark.done then
    if v_was <> 'completed' and v_row."status" = 'completed' then
      null;
    end if;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."enrollment_mark"(uuid, text, boolean, uuid) from public, anon, authenticated;

-- Creates or changes a program. program is { id?, version?, key, name,
-- description, subjectTypes, steps, enabled }; keys left out keep their value.
-- Changing the steps raises the version. version, when given, must be the
-- stored one.
create or replace function "better_supabase"."save_enrollment_program"(tenant uuid, program jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."enrollment_programs";
  v_row "better_supabase"."enrollment_programs";
  v_key text;
  v_name text;
  v_description text;
  v_types text[];
  v_steps jsonb;
  v_enabled boolean;
  v_step jsonb;
  v_ids text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_enrollment_program.tenant is not null and coalesce(better_supabase.can('tenant', save_enrollment_program.tenant, 'enrollments.manage'), false))) then
    raise exception 'not allowed to manage enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if save_enrollment_program.program is null or jsonb_typeof(save_enrollment_program.program) <> 'object' then
    raise exception 'program must be an object' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_id := nullif(save_enrollment_program.program ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."enrollment_programs" x
    where x."id" = v_id and x."tenant_id" = save_enrollment_program.tenant
    for update;
    if v_old."id" is null then
      raise exception 'enrollment program not found' using errcode = 'P0002', hint = 'ENROLLMENTS_PROGRAM_NOT_FOUND';
    end if;
    if save_enrollment_program.program ? 'version' and (save_enrollment_program.program ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'the program changed since you read it' using errcode = '40001', hint = 'ENROLLMENTS_PROGRAM_CONFLICT';
    end if;
  end if;
  if save_enrollment_program.program ? 'subjectTypes' and jsonb_typeof(save_enrollment_program.program -> 'subjectTypes') <> 'array' then
    raise exception 'subjectTypes must be an array of subject types' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_key := coalesce(save_enrollment_program.program ->> 'key', v_old."key");
  v_name := trim(coalesce(save_enrollment_program.program ->> 'name', v_old."name"));
  v_description := case when save_enrollment_program.program ? 'description'
    then nullif(trim(save_enrollment_program.program ->> 'description'), '') else v_old."description" end;
  v_types := case when save_enrollment_program.program ? 'subjectTypes'
    then array(select t.value from jsonb_array_elements_text(save_enrollment_program.program -> 'subjectTypes') with ordinality as t(value, ord) order by t.ord)
    else coalesce(v_old."subject_types", '{}') end;
  v_steps := case when save_enrollment_program.program ? 'steps'
    then save_enrollment_program.program -> 'steps' else coalesce(v_old."steps", '[]'::jsonb) end;
  v_enabled := case when save_enrollment_program.program ? 'enabled'
    then (save_enrollment_program.program ->> 'enabled')::boolean else coalesce(v_old."enabled", true) end;
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'key: use lowercase letters, digits, "_" or "-", starting with a letter' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_old."id" is not null and v_key <> v_old."key" then
    raise exception 'a program''s key can''t change' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_name is null or length(v_name) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if length(v_description) > 2000 then
    raise exception 'description must be at most 2000 characters' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if exists (select 1 from unnest(v_types) as t(value) where t.value is null or t.value !~ '^[a-z][a-z0-9_-]{0,62}$') then
    raise exception 'subjectTypes must be lower-case subject types' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) = 0 then
    raise exception 'steps: pass at least one step' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if jsonb_array_length(v_steps) > 100 then
    raise exception 'a program holds at most 100 steps' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  for v_step in select t.value from jsonb_array_elements(v_steps) as t(value) loop
    if jsonb_typeof(v_step) <> 'object' or coalesce(v_step ->> 'id', '') !~ '^[a-z][a-z0-9_.-]{0,63}$' then
      raise exception 'each step needs an id of lowercase letters, digits, "_", "." or "-"' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    if (v_step ->> 'id') = any(v_ids) then
      raise exception 'step ids must be unique' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    if length(v_step ->> 'title') > 200 or length(v_step ->> 'description') > 2000 then
      raise exception 'a step title holds at most 200 characters and a description 2000' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    v_ids := v_ids || (v_step ->> 'id');
  end loop;
  v_steps := (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', t.value ->> 'id', 'title', t.value ->> 'title', 'description', t.value ->> 'description')) order by t.ord)
    from jsonb_array_elements(v_steps) with ordinality as t(value, ord)
  );
  if v_old."id" is null then
    insert into "better_supabase"."enrollment_programs" ("tenant_id", "key", "name", "description", "subject_types", "steps", "enabled", "created_by")
    values (save_enrollment_program.tenant, v_key, v_name, v_description, v_types, v_steps, v_enabled, auth.uid())
    on conflict ("tenant_id", "key") do nothing
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'a program with this key already exists' using errcode = '23505', hint = 'ENROLLMENTS_PROGRAM_EXISTS';
    end if;
  else
    update "better_supabase"."enrollment_programs" x
    set "name" = v_name, "description" = v_description, "subject_types" = v_types, "steps" = v_steps,
      "enabled" = v_enabled,
      "version" = x."version" + case when x."steps" is distinct from v_steps then 1 else 0 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectTypes', to_jsonb(v_row."subject_types"), 'steps', v_row."steps", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_enrollment_program"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_enrollment_program"(uuid, jsonb) to authenticated, service_role;

-- The organization's programs by key.
create or replace function "better_supabase"."enrollment_programs"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enrollment_programs.tenant is not null and coalesce(better_supabase.can('tenant', enrollment_programs.tenant, 'enrollments.read'), false))) then
    raise exception 'not allowed to read enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectTypes', to_jsonb(x."subject_types"), 'steps', x."steps", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."key")
    from "better_supabase"."enrollment_programs" x where x."tenant_id" = enrollment_programs.tenant
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."enrollment_programs"(uuid) from public, anon;
grant execute on function "better_supabase"."enrollment_programs"(uuid) to authenticated, service_role;

-- Deletes a program with its enrollments; false when it was already gone.
create or replace function "better_supabase"."delete_enrollment_program"(program_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."enrollment_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."enrollment_programs" x where x."id" = delete_enrollment_program.program_id for update;
  if v_row."id" is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.manage'), false))) then
    raise exception 'not allowed to manage enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  delete from "better_supabase"."enrollments" x where x."tenant_id" = v_row."tenant_id" and x."program" = v_row."key";
  delete from "better_supabase"."enrollment_programs" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_enrollment_program"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_enrollment_program"(uuid) to authenticated, service_role;

-- Enrolls a subject in a program; returns the enrollment. Enrolling an
-- enrolled subject returns its enrollment, and enrolling a cancelled one
-- starts it again with its completed steps.
create or replace function "better_supabase"."enroll"(tenant uuid, program text, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_program "better_supabase"."enrollment_programs";
  v_row "better_supabase"."enrollments";
  v_id uuid;
  v_steps text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enroll.tenant is not null and coalesce(better_supabase.can('tenant', enroll.tenant, 'enrollments.enroll'), false))) then
    raise exception 'not allowed to enroll' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  select * into v_program from "better_supabase"."enrollment_programs" x
  where x."tenant_id" = enroll.tenant and x."key" = enroll.program;
  if v_program."id" is null then
    raise exception 'enrollment program not found' using errcode = 'P0002', hint = 'ENROLLMENTS_PROGRAM_NOT_FOUND';
  end if;
  if not v_program."enabled" then
    raise exception 'this program is turned off' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if enroll.subject_type is null or enroll.subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' or enroll.subject_id is null or length(enroll.subject_id) not between 1 and 200 then
    raise exception 'an enrollment needs a subject type and id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if cardinality(v_program."subject_types") > 0 and not (enroll.subject_type = any(v_program."subject_types")) then
    raise exception 'this program doesn''t enroll this subject type' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if enroll.subject_type = 'user' and enroll.subject_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'a user subject needs a user id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_steps := array(select t.value ->> 'id' from jsonb_array_elements(v_program."steps") with ordinality as t(value, ord) order by t.ord);
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = enroll.tenant and x."program" = enroll.program
    and x."subject_type" = enroll.subject_type and x."subject_id" = enroll.subject_id
  for update;
  if v_row."status" = 'cancelled' then
    update "better_supabase"."enrollments" x
    set "status" = 'active', "cancelled_at" = null, "enrolled_by" = auth.uid(), "enrolled_at" = now(),
      "steps" = v_steps, "program_version" = v_program."version"
    where x."id" = v_row."id";
    update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = better_supabase.as_column_type(case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end, (null::"better_supabase"."enrollments")."status"),
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
    v_id := v_row."id";
  else
    v_id := "better_supabase"."enrollment_ensure"(enroll.tenant, enroll.program, v_program."version", v_steps, enroll.subject_type, enroll.subject_id, auth.uid());
  end if;
  return "better_supabase"."enrollment_json"(v_id);
end;
$$;
revoke execute on function "better_supabase"."enroll"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."enroll"(uuid, text, text, text) to authenticated, service_role;

-- A subject's enrollment in a program, or null. A user reads their own.
create or replace function "better_supabase"."enrollment"(tenant uuid, program text, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enrollment.tenant is not null and coalesce(better_supabase.can('tenant', enrollment.tenant, 'enrollments.read'), false))) or (enrollment.subject_type = 'user' and enrollment.subject_id = auth.uid()::text)) then
    raise exception 'not allowed to read enrollments' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  select x."id" into v_id from "better_supabase"."enrollments" x
  where x."tenant_id" = enrollment.tenant and x."program" = enrollment.program
    and x."subject_type" = enrollment.subject_type and x."subject_id" = enrollment.subject_id;
  return case when v_id is null then null else "better_supabase"."enrollment_json"(v_id) end;
end;
$$;
revoke execute on function "better_supabase"."enrollment"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."enrollment"(uuid, text, text, text) to authenticated, service_role;

-- The organization's enrollments, most recently changed first. Without
-- enrollments.read a member sees only their own.
create or replace function "better_supabase"."list_enrollments"(tenant uuid, program text default null, subject_type text default null, subject_id text default null, status text default null, page_size integer default null, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_read boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', list_enrollments.tenant, 'enrollments.read'), false)));
begin
  if not v_read and auth.uid() is null then
    raise exception 'not allowed to read enrollments' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if list_enrollments.status is not null and list_enrollments.status not in ('active', 'completed', 'cancelled') then
    raise exception 'status must be active, completed or cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  return coalesce((
    select jsonb_agg("better_supabase"."enrollment_json"(y."id") order by y."updated_at" desc, y."id")
    from (
      select x."id", x."updated_at" from "better_supabase"."enrollments" x
      where x."tenant_id" = list_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (list_enrollments.program is null or x."program" = list_enrollments.program)
        and (list_enrollments.subject_type is null or x."subject_type" = list_enrollments.subject_type)
        and (list_enrollments.subject_id is null or x."subject_id" = list_enrollments.subject_id)
        and (list_enrollments.status is null or x."status" = better_supabase.as_column_type(list_enrollments.status, (null::"better_supabase"."enrollments")."status"))
        and (list_enrollments.before is null or x."updated_at" < list_enrollments.before)
      order by x."updated_at" desc, x."id"
      limit least(greatest(coalesce(list_enrollments.page_size, 50), 1), 200)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_enrollments"(uuid, text, text, text, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_enrollments"(uuid, text, text, text, text, integer, timestamptz) to authenticated, service_role;

-- Marks a step of an enrollment done or not done: enrollments.enroll, or the
-- enrolled user for their own.
create or replace function "better_supabase"."enrollment_step"(enrollment_id uuid, step text, done boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."enrollments";
begin
  select * into v_row from "better_supabase"."enrollments" x where x."id" = enrollment_step.enrollment_id;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.read'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.enroll'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'not allowed to change this enrollment' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  -- A course's steps follow its lessons, so they change only through courses.
  if v_row."program" like 'course:%' then
    raise exception 'this enrollment belongs to a course; complete its lessons through courses' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  -- A sequence's steps run on its schedule, so only its runner marks them.
  if v_row."program" like 'sequence:%' then
    raise exception 'this enrollment belongs to a sequence; its steps run on the sequence''s schedule' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  perform "better_supabase"."enrollment_mark"(v_row."id", enrollment_step.step, enrollment_step.done, auth.uid());
  return "better_supabase"."enrollment_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."enrollment_step"(uuid, text, boolean) from public, anon, authenticated;

create or replace function "better_supabase"."complete_enrollment_step"(enrollment_id uuid, step text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."enrollment_step"(complete_enrollment_step.enrollment_id, complete_enrollment_step.step, true)
$$;
revoke execute on function "better_supabase"."complete_enrollment_step"(uuid, text) from public, anon;
grant execute on function "better_supabase"."complete_enrollment_step"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."reset_enrollment_step"(enrollment_id uuid, step text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."enrollment_step"(reset_enrollment_step.enrollment_id, reset_enrollment_step.step, false)
$$;
revoke execute on function "better_supabase"."reset_enrollment_step"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reset_enrollment_step"(uuid, text) to authenticated, service_role;

-- Cancels an active enrollment; its completed steps stay. A cancelled one is
-- returned as it is. Programs a module drives can't be cancelled.
create or replace function "better_supabase"."cancel_enrollment"(enrollment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."enrollments" x where x."id" = cancel_enrollment.enrollment_id for update;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.read'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.enroll'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'not allowed to change this enrollment' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if position(':' in v_row."program") > 0 then
    raise exception 'this enrollment belongs to a module and can''t be cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'completed' then
    raise exception 'a completed enrollment can''t be cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'active' then
    update "better_supabase"."enrollments" x
    set "status" = 'cancelled', "cancelled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  return "better_supabase"."enrollment_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."cancel_enrollment"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_enrollment"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_programs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_select on "better_supabase"."enrollment_programs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_insert on "better_supabase"."enrollment_programs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_update on "better_supabase"."enrollment_programs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_delete on "better_supabase"."enrollment_programs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."enrollments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollments";
create policy bsb_tenant_scope_select on "better_supabase"."enrollments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('enrollments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollments";
create policy bsb_tenant_scope_insert on "better_supabase"."enrollments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollments";
create policy bsb_tenant_scope_update on "better_supabase"."enrollments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollments";
create policy bsb_tenant_scope_delete on "better_supabase"."enrollments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_steps";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_select on "better_supabase"."enrollment_steps" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."enrollments" x where x."id" = "better_supabase"."enrollment_steps"."enrollment_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_insert on "better_supabase"."enrollment_steps" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_update on "better_supabase"."enrollment_steps" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_delete on "better_supabase"."enrollment_steps" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_036_enrollments.sql
-- better-supabase module: enrollments
-- @bsb-block-data enrollments
-- @bsb-hash sha256:ba27786140fd499c4d1e2ab814ef20ead1970f014ec0279b82377d83afb2017a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('enrollments', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_036_enrollments.sql
-- better-supabase module: enrollments
-- @bsb-block enrollments@1 managed
-- @bsb-hash sha256:7854fd9f65398a7cec2a944280d69b130160cf05be13952ba3ba4f36fc4cdffd
-- Programs of steps per organization, and enrollments of a party, a member or any subject in them with step progress and completion. Onboarding checklists run on it.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_programs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_programs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_steps";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_steps";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."enrollment_programs" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  -- The subject types it enrolls; empty enrolls any.
  "subject_types" text[] not null default '{}',
  -- [{ id, title, description }], in order.
  "steps" jsonb not null default '[]'::jsonb check (jsonb_typeof("steps") = 'array'),
  "enabled" boolean not null default true,
  "version" integer not null default 1,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "key")
);

-- One per program and subject. A user's own onboarding checklist has no
-- tenant; user_id is set for user subjects so the row goes with the user.
create table if not exists "better_supabase"."enrollments" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid,
  "program" text not null check (length("program") between 1 and 200),
  "program_version" integer,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "user_id" uuid references auth.users (id) on delete cascade,
  -- The program's step ids when it enrolled or last changed.
  "steps" text[] not null default '{}',
  "completed_steps" integer not null default 0 check ("completed_steps" >= 0),
  "status" text not null default 'active' check ("status" in ('active', 'completed', 'cancelled')),
  "enrolled_by" uuid,
  "enrolled_at" timestamptz not null default now(),
  "completed_at" timestamptz,
  "cancelled_at" timestamptz,
  "updated_at" timestamptz not null default now(),
  check (("subject_type" = 'user') = ("user_id" is not null)),
  check ("user_id" is null or "subject_id" = "user_id"::text),
  unique nulls not distinct ("org_id", "program", "subject_type", "subject_id")
);
create index if not exists "enrollments_program_idx" on "better_supabase"."enrollments" ("org_id", "program", "status");
create index if not exists "enrollments_subject_idx" on "better_supabase"."enrollments" ("org_id", "subject_type", "subject_id");
create index if not exists "enrollments_user_idx" on "better_supabase"."enrollments" ("user_id");

create table if not exists "better_supabase"."enrollment_steps" (
  "enrollment_id" uuid not null references "better_supabase"."enrollments" ("id") on delete cascade,
  "org_id" uuid,
  "step" text not null,
  "completed_by" uuid,
  "completed_at" timestamptz not null default now(),
  primary key ("enrollment_id", "step")
);

alter table "better_supabase"."enrollment_programs" enable row level security;
revoke all on "better_supabase"."enrollment_programs" from public, anon, authenticated;
grant select on "better_supabase"."enrollment_programs" to authenticated;
grant all on "better_supabase"."enrollment_programs" to service_role;
drop policy if exists "enrollment_programs_read" on "better_supabase"."enrollment_programs";
create policy enrollment_programs_read on "better_supabase"."enrollment_programs"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('enrollments.read')));
alter table "better_supabase"."enrollments" enable row level security;
revoke all on "better_supabase"."enrollments" from public, anon, authenticated;
grant select on "better_supabase"."enrollments" to authenticated;
grant all on "better_supabase"."enrollments" to service_role;
drop policy if exists "enrollments_read" on "better_supabase"."enrollments";
create policy enrollments_read on "better_supabase"."enrollments"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('enrollments.read')));
alter table "better_supabase"."enrollment_steps" enable row level security;
revoke all on "better_supabase"."enrollment_steps" from public, anon, authenticated;
grant select on "better_supabase"."enrollment_steps" to authenticated;
grant all on "better_supabase"."enrollment_steps" to service_role;
drop policy if exists "enrollment_steps_read" on "better_supabase"."enrollment_steps";
create policy enrollment_steps_read on "better_supabase"."enrollment_steps"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."enrollments" x where x."id" = "better_supabase"."enrollment_steps"."enrollment_id"));

-- An enrollment with its steps and the completed ones, oldest first.
create or replace function "better_supabase"."enrollment_json"(enrollment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id", 'organizationId', x."org_id", 'program', x."program", 'programVersion', x."program_version",
    'subjectType', x."subject_type", 'subjectId', x."subject_id", 'status', x."status",
    'steps', to_jsonb(x."steps"), 'completedSteps', x."completed_steps", 'totalSteps', cardinality(x."steps"),
    'enrolledBy', x."enrolled_by", 'enrolledAt', x."enrolled_at", 'completedAt', x."completed_at",
    'cancelledAt', x."cancelled_at", 'updatedAt', x."updated_at",
    'progress', coalesce((
      select jsonb_agg(jsonb_build_object('step', y."step", 'completedAt', y."completed_at", 'completedBy', y."completed_by") order by y."completed_at", array_position(x."steps", y."step"), y."step")
      from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id"
    ), '[]'::jsonb)
  )
  from "better_supabase"."enrollments" x
  where x."id" = enrollment_json.enrollment_id
$$;
revoke execute on function "better_supabase"."enrollment_json"(uuid) from public, anon, authenticated;

-- The enrollment of a subject in a program, created when missing. steps are
-- the program's step ids; when they changed, the enrollment takes them and
-- recounts. For this module and modules that drive their own programs, such
-- as onboarding (program keys with a colon).
create or replace function "better_supabase"."enrollment_ensure"(tenant uuid, program text, program_version integer, steps text[], subject_type text, subject_id text, actor uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."enrollments";
begin
  select * into v_row from "better_supabase"."enrollments" x
  where x."org_id" is not distinct from enrollment_ensure.tenant and x."program" = enrollment_ensure.program
    and x."subject_type" = enrollment_ensure.subject_type and x."subject_id" = enrollment_ensure.subject_id
  for update;
  if v_row."id" is null then
    insert into "better_supabase"."enrollments" ("org_id", "program", "program_version", "subject_type", "subject_id", "user_id", "steps", "enrolled_by")
    values (enrollment_ensure.tenant, enrollment_ensure.program, enrollment_ensure.program_version, enrollment_ensure.subject_type, enrollment_ensure.subject_id, case when enrollment_ensure.subject_type = 'user' then enrollment_ensure.subject_id::uuid end, enrollment_ensure.steps, enrollment_ensure.actor)
    on conflict do nothing
    returning * into v_row;
    if v_row."id" is null then
      select * into v_row from "better_supabase"."enrollments" x
      where x."org_id" is not distinct from enrollment_ensure.tenant and x."program" = enrollment_ensure.program
        and x."subject_type" = enrollment_ensure.subject_type and x."subject_id" = enrollment_ensure.subject_id;
      return v_row."id";
    end if;
    return v_row."id";
  end if;
  if v_row."steps" is distinct from enrollment_ensure.steps or v_row."program_version" is distinct from enrollment_ensure.program_version then
    update "better_supabase"."enrollments" x set "steps" = enrollment_ensure.steps, "program_version" = enrollment_ensure.program_version
    where x."id" = v_row."id";
    update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  end if;
  return v_row."id";
end;
$$;
revoke execute on function "better_supabase"."enrollment_ensure"(uuid, text, integer, text[], text, text, uuid) from public, anon, authenticated;

-- Marks a step done or not done without a permission check; false when it
-- already was. Emits enrollment.step_completed and enrollment.completed for
-- enrollments in an organization.
create or replace function "better_supabase"."enrollment_mark"(enrollment_id uuid, step text, done boolean, actor uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."enrollments";
  v_was text;
  v_count integer;
begin
  select * into v_row from "better_supabase"."enrollments" x where x."id" = enrollment_mark.enrollment_id for update;
  if v_row."id" is null then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if enrollment_mark.step is null or not (enrollment_mark.step = any(v_row."steps")) then
    raise exception 'this step is not part of the program' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'cancelled' then
    raise exception 'the enrollment is cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_was := v_row."status";
  if enrollment_mark.done then
    insert into "better_supabase"."enrollment_steps" ("enrollment_id", "org_id", "step", "completed_by")
    values (v_row."id", v_row."org_id", enrollment_mark.step, enrollment_mark.actor)
    on conflict do nothing;
  else
    delete from "better_supabase"."enrollment_steps" x where x."enrollment_id" = v_row."id" and x."step" = enrollment_mark.step;
  end if;
  get diagnostics v_count = row_count;
  if v_count = 0 then
    return false;
  end if;
  update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if enrollment_mark.done then
    if v_was <> 'completed' and v_row."status" = 'completed' then
      null;
    end if;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."enrollment_mark"(uuid, text, boolean, uuid) from public, anon, authenticated;

-- Creates or changes a program. program is { id?, version?, key, name,
-- description, subjectTypes, steps, enabled }; keys left out keep their value.
-- Changing the steps raises the version. version, when given, must be the
-- stored one.
create or replace function "better_supabase"."save_enrollment_program"(tenant uuid, program jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."enrollment_programs";
  v_row "better_supabase"."enrollment_programs";
  v_key text;
  v_name text;
  v_description text;
  v_types text[];
  v_steps jsonb;
  v_enabled boolean;
  v_step jsonb;
  v_ids text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_enrollment_program.tenant is not null and coalesce(better_supabase.can('tenant', save_enrollment_program.tenant, 'enrollments.manage'), false))) then
    raise exception 'not allowed to manage enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if save_enrollment_program.program is null or jsonb_typeof(save_enrollment_program.program) <> 'object' then
    raise exception 'program must be an object' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_id := nullif(save_enrollment_program.program ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."enrollment_programs" x
    where x."id" = v_id and x."org_id" = save_enrollment_program.tenant
    for update;
    if v_old."id" is null then
      raise exception 'enrollment program not found' using errcode = 'P0002', hint = 'ENROLLMENTS_PROGRAM_NOT_FOUND';
    end if;
    if save_enrollment_program.program ? 'version' and (save_enrollment_program.program ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'the program changed since you read it' using errcode = '40001', hint = 'ENROLLMENTS_PROGRAM_CONFLICT';
    end if;
  end if;
  if save_enrollment_program.program ? 'subjectTypes' and jsonb_typeof(save_enrollment_program.program -> 'subjectTypes') <> 'array' then
    raise exception 'subjectTypes must be an array of subject types' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_key := coalesce(save_enrollment_program.program ->> 'key', v_old."key");
  v_name := trim(coalesce(save_enrollment_program.program ->> 'name', v_old."name"));
  v_description := case when save_enrollment_program.program ? 'description'
    then nullif(trim(save_enrollment_program.program ->> 'description'), '') else v_old."description" end;
  v_types := case when save_enrollment_program.program ? 'subjectTypes'
    then array(select t.value from jsonb_array_elements_text(save_enrollment_program.program -> 'subjectTypes') with ordinality as t(value, ord) order by t.ord)
    else coalesce(v_old."subject_types", '{}') end;
  v_steps := case when save_enrollment_program.program ? 'steps'
    then save_enrollment_program.program -> 'steps' else coalesce(v_old."steps", '[]'::jsonb) end;
  v_enabled := case when save_enrollment_program.program ? 'enabled'
    then (save_enrollment_program.program ->> 'enabled')::boolean else coalesce(v_old."enabled", true) end;
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'key: use lowercase letters, digits, "_" or "-", starting with a letter' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_old."id" is not null and v_key <> v_old."key" then
    raise exception 'a program''s key can''t change' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_name is null or length(v_name) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if length(v_description) > 2000 then
    raise exception 'description must be at most 2000 characters' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if exists (select 1 from unnest(v_types) as t(value) where t.value is null or t.value !~ '^[a-z][a-z0-9_-]{0,62}$') then
    raise exception 'subjectTypes must be lower-case subject types' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) = 0 then
    raise exception 'steps: pass at least one step' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if jsonb_array_length(v_steps) > 100 then
    raise exception 'a program holds at most 100 steps' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  for v_step in select t.value from jsonb_array_elements(v_steps) as t(value) loop
    if jsonb_typeof(v_step) <> 'object' or coalesce(v_step ->> 'id', '') !~ '^[a-z][a-z0-9_.-]{0,63}$' then
      raise exception 'each step needs an id of lowercase letters, digits, "_", "." or "-"' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    if (v_step ->> 'id') = any(v_ids) then
      raise exception 'step ids must be unique' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    if length(v_step ->> 'title') > 200 or length(v_step ->> 'description') > 2000 then
      raise exception 'a step title holds at most 200 characters and a description 2000' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    v_ids := v_ids || (v_step ->> 'id');
  end loop;
  v_steps := (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', t.value ->> 'id', 'title', t.value ->> 'title', 'description', t.value ->> 'description')) order by t.ord)
    from jsonb_array_elements(v_steps) with ordinality as t(value, ord)
  );
  if v_old."id" is null then
    insert into "better_supabase"."enrollment_programs" ("org_id", "key", "name", "description", "subject_types", "steps", "enabled", "created_by")
    values (save_enrollment_program.tenant, v_key, v_name, v_description, v_types, v_steps, v_enabled, auth.uid())
    on conflict ("org_id", "key") do nothing
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'a program with this key already exists' using errcode = '23505', hint = 'ENROLLMENTS_PROGRAM_EXISTS';
    end if;
  else
    update "better_supabase"."enrollment_programs" x
    set "name" = v_name, "description" = v_description, "subject_types" = v_types, "steps" = v_steps,
      "enabled" = v_enabled,
      "version" = x."version" + case when x."steps" is distinct from v_steps then 1 else 0 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectTypes', to_jsonb(v_row."subject_types"), 'steps', v_row."steps", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_enrollment_program"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_enrollment_program"(uuid, jsonb) to authenticated, service_role;

-- The organization's programs by key.
create or replace function "better_supabase"."enrollment_programs"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enrollment_programs.tenant is not null and coalesce(better_supabase.can('tenant', enrollment_programs.tenant, 'enrollments.read'), false))) then
    raise exception 'not allowed to read enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectTypes', to_jsonb(x."subject_types"), 'steps', x."steps", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."key")
    from "better_supabase"."enrollment_programs" x where x."org_id" = enrollment_programs.tenant
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."enrollment_programs"(uuid) from public, anon;
grant execute on function "better_supabase"."enrollment_programs"(uuid) to authenticated, service_role;

-- Deletes a program with its enrollments; false when it was already gone.
create or replace function "better_supabase"."delete_enrollment_program"(program_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."enrollment_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."enrollment_programs" x where x."id" = delete_enrollment_program.program_id for update;
  if v_row."id" is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'enrollments.manage'), false))) then
    raise exception 'not allowed to manage enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  delete from "better_supabase"."enrollments" x where x."org_id" = v_row."org_id" and x."program" = v_row."key";
  delete from "better_supabase"."enrollment_programs" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_enrollment_program"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_enrollment_program"(uuid) to authenticated, service_role;

-- Enrolls a subject in a program; returns the enrollment. Enrolling an
-- enrolled subject returns its enrollment, and enrolling a cancelled one
-- starts it again with its completed steps.
create or replace function "better_supabase"."enroll"(tenant uuid, program text, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_program "better_supabase"."enrollment_programs";
  v_row "better_supabase"."enrollments";
  v_id uuid;
  v_steps text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enroll.tenant is not null and coalesce(better_supabase.can('tenant', enroll.tenant, 'enrollments.enroll'), false))) then
    raise exception 'not allowed to enroll' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  select * into v_program from "better_supabase"."enrollment_programs" x
  where x."org_id" = enroll.tenant and x."key" = enroll.program;
  if v_program."id" is null then
    raise exception 'enrollment program not found' using errcode = 'P0002', hint = 'ENROLLMENTS_PROGRAM_NOT_FOUND';
  end if;
  if not v_program."enabled" then
    raise exception 'this program is turned off' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if enroll.subject_type is null or enroll.subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' or enroll.subject_id is null or length(enroll.subject_id) not between 1 and 200 then
    raise exception 'an enrollment needs a subject type and id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if cardinality(v_program."subject_types") > 0 and not (enroll.subject_type = any(v_program."subject_types")) then
    raise exception 'this program doesn''t enroll this subject type' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if enroll.subject_type = 'user' and enroll.subject_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'a user subject needs a user id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_steps := array(select t.value ->> 'id' from jsonb_array_elements(v_program."steps") with ordinality as t(value, ord) order by t.ord);
  select * into v_row from "better_supabase"."enrollments" x
  where x."org_id" = enroll.tenant and x."program" = enroll.program
    and x."subject_type" = enroll.subject_type and x."subject_id" = enroll.subject_id
  for update;
  if v_row."status" = 'cancelled' then
    update "better_supabase"."enrollments" x
    set "status" = 'active', "cancelled_at" = null, "enrolled_by" = auth.uid(), "enrolled_at" = now(),
      "steps" = v_steps, "program_version" = v_program."version"
    where x."id" = v_row."id";
    update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps")) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
    v_id := v_row."id";
  else
    v_id := "better_supabase"."enrollment_ensure"(enroll.tenant, enroll.program, v_program."version", v_steps, enroll.subject_type, enroll.subject_id, auth.uid());
  end if;
  return "better_supabase"."enrollment_json"(v_id);
end;
$$;
revoke execute on function "better_supabase"."enroll"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."enroll"(uuid, text, text, text) to authenticated, service_role;

-- A subject's enrollment in a program, or null. A user reads their own.
create or replace function "better_supabase"."enrollment"(tenant uuid, program text, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enrollment.tenant is not null and coalesce(better_supabase.can('tenant', enrollment.tenant, 'enrollments.read'), false))) or (enrollment.subject_type = 'user' and enrollment.subject_id = auth.uid()::text)) then
    raise exception 'not allowed to read enrollments' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  select x."id" into v_id from "better_supabase"."enrollments" x
  where x."org_id" = enrollment.tenant and x."program" = enrollment.program
    and x."subject_type" = enrollment.subject_type and x."subject_id" = enrollment.subject_id;
  return case when v_id is null then null else "better_supabase"."enrollment_json"(v_id) end;
end;
$$;
revoke execute on function "better_supabase"."enrollment"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."enrollment"(uuid, text, text, text) to authenticated, service_role;

-- The organization's enrollments, most recently changed first. Without
-- enrollments.read a member sees only their own.
create or replace function "better_supabase"."list_enrollments"(tenant uuid, program text default null, subject_type text default null, subject_id text default null, status text default null, page_size integer default null, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_read boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', list_enrollments.tenant, 'enrollments.read'), false)));
begin
  if not v_read and auth.uid() is null then
    raise exception 'not allowed to read enrollments' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if list_enrollments.status is not null and list_enrollments.status not in ('active', 'completed', 'cancelled') then
    raise exception 'status must be active, completed or cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  return coalesce((
    select jsonb_agg("better_supabase"."enrollment_json"(y."id") order by y."updated_at" desc, y."id")
    from (
      select x."id", x."updated_at" from "better_supabase"."enrollments" x
      where x."org_id" = list_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (list_enrollments.program is null or x."program" = list_enrollments.program)
        and (list_enrollments.subject_type is null or x."subject_type" = list_enrollments.subject_type)
        and (list_enrollments.subject_id is null or x."subject_id" = list_enrollments.subject_id)
        and (list_enrollments.status is null or x."status" = list_enrollments.status)
        and (list_enrollments.before is null or x."updated_at" < list_enrollments.before)
      order by x."updated_at" desc, x."id"
      limit least(greatest(coalesce(list_enrollments.page_size, 50), 1), 200)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_enrollments"(uuid, text, text, text, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_enrollments"(uuid, text, text, text, text, integer, timestamptz) to authenticated, service_role;

-- Marks a step of an enrollment done or not done: enrollments.enroll, or the
-- enrolled user for their own.
create or replace function "better_supabase"."enrollment_step"(enrollment_id uuid, step text, done boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."enrollments";
begin
  select * into v_row from "better_supabase"."enrollments" x where x."id" = enrollment_step.enrollment_id;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'enrollments.read'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'enrollments.enroll'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'not allowed to change this enrollment' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  -- A course's steps follow its lessons, so they change only through courses.
  if v_row."program" like 'course:%' then
    raise exception 'this enrollment belongs to a course; complete its lessons through courses' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  -- A sequence's steps run on its schedule, so only its runner marks them.
  if v_row."program" like 'sequence:%' then
    raise exception 'this enrollment belongs to a sequence; its steps run on the sequence''s schedule' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  perform "better_supabase"."enrollment_mark"(v_row."id", enrollment_step.step, enrollment_step.done, auth.uid());
  return "better_supabase"."enrollment_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."enrollment_step"(uuid, text, boolean) from public, anon, authenticated;

create or replace function "better_supabase"."complete_enrollment_step"(enrollment_id uuid, step text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."enrollment_step"(complete_enrollment_step.enrollment_id, complete_enrollment_step.step, true)
$$;
revoke execute on function "better_supabase"."complete_enrollment_step"(uuid, text) from public, anon;
grant execute on function "better_supabase"."complete_enrollment_step"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."reset_enrollment_step"(enrollment_id uuid, step text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."enrollment_step"(reset_enrollment_step.enrollment_id, reset_enrollment_step.step, false)
$$;
revoke execute on function "better_supabase"."reset_enrollment_step"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reset_enrollment_step"(uuid, text) to authenticated, service_role;

-- Cancels an active enrollment; its completed steps stay. A cancelled one is
-- returned as it is. Programs a module drives can't be cancelled.
create or replace function "better_supabase"."cancel_enrollment"(enrollment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."enrollments" x where x."id" = cancel_enrollment.enrollment_id for update;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'enrollments.read'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'enrollments.enroll'), false))) or (v_row."user_id" is not null and v_row."user_id" = auth.uid())) then
    raise exception 'not allowed to change this enrollment' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if position(':' in v_row."program") > 0 then
    raise exception 'this enrollment belongs to a module and can''t be cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'completed' then
    raise exception 'a completed enrollment can''t be cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'active' then
    update "better_supabase"."enrollments" x
    set "status" = 'cancelled', "cancelled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  return "better_supabase"."enrollment_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."cancel_enrollment"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_enrollment"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_programs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_select on "better_supabase"."enrollment_programs" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('enrollments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_insert on "better_supabase"."enrollment_programs" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_update on "better_supabase"."enrollment_programs" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_programs";
create policy bsb_tenant_scope_delete on "better_supabase"."enrollment_programs" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."enrollments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollments";
create policy bsb_tenant_scope_select on "better_supabase"."enrollments" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('enrollments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollments";
create policy bsb_tenant_scope_insert on "better_supabase"."enrollments" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollments";
create policy bsb_tenant_scope_update on "better_supabase"."enrollments" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollments";
create policy bsb_tenant_scope_delete on "better_supabase"."enrollments" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."enrollment_steps";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_select on "better_supabase"."enrollment_steps" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."enrollments" x where x."id" = "better_supabase"."enrollment_steps"."enrollment_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_insert on "better_supabase"."enrollment_steps" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_update on "better_supabase"."enrollment_steps" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrollment_steps";
create policy bsb_tenant_scope_delete on "better_supabase"."enrollment_steps" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_036_enrollments.sql
-- better-supabase module: enrollments
-- @bsb-block-data enrollments
-- @bsb-hash sha256:ba27786140fd499c4d1e2ab814ef20ead1970f014ec0279b82377d83afb2017a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('enrollments', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
