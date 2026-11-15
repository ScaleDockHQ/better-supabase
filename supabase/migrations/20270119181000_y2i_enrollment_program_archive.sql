SET local check_function_bodies = off;

DROP FUNCTION "api"."delete_enrollment_program"(uuid);

DROP FUNCTION "api"."enrollment_programs"(uuid);

DROP FUNCTION "better_supabase"."delete_enrollment_program"(uuid);

DROP FUNCTION "better_supabase"."enrollment_programs"(uuid);

ALTER TABLE "better_supabase"."enrollment_programs"
  ADD COLUMN "archived_at" timestamp WITH time zone;

CREATE OR REPLACE FUNCTION api.archive_enrollment_program (
  program_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_enrollment_program"($1) $function$;

CREATE OR REPLACE FUNCTION api.enrollment_programs (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."enrollment_programs"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.purge_enrollment_program (
  program_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_enrollment_program"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_enrollment_program (
  program_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_enrollment_program"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_enrollment_program (
  program_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."enrollment_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."enrollment_programs" x where x."id" = archive_enrollment_program.program_id for update;
  if v_row."id" is null then
    raise exception 'enrollment program not found' using errcode = 'P0002', hint = 'ENROLLMENTS_PROGRAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.manage'), false))) then
    raise exception 'not allowed to manage enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectTypes', to_jsonb(v_row."subject_types"), 'steps', v_row."steps", 'enabled', v_row."enabled", 'archivedAt', v_row."archived_at", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."enrollment_programs" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('enrollment_program.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version"), 'enrollment-programs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  perform better_supabase.audit_event(
    event_type => 'enrollment_program.archived',
    category => 'data',
    target_type => 'enrollment_program',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'archived an enrollment program',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectTypes', to_jsonb(v_row."subject_types"), 'steps', v_row."steps", 'enabled', v_row."enabled", 'archivedAt', v_row."archived_at", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.enroll (
  tenant       uuid,
  program      text,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
  if v_program."archived_at" is not null then
    raise exception 'program is archived; restore it first' using errcode = '55000', hint = 'ENROLLMENTS_PROGRAM_ARCHIVED';
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
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_enrollment_create"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using enroll.tenant, enroll.program, enroll.subject_type, enroll.subject_id;
    end if;
  end;
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
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps") and y."completed_at" is not null),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps") and y."completed_at" is not null) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps") and y."completed_at" is not null) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
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
  perform "better_supabase"."enrollment_schedule"(v_id);
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_enrollment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return "better_supabase"."enrollment_json"(v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.enrollment_programs (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enrollment_programs.tenant is not null and coalesce(better_supabase.can('tenant', enrollment_programs.tenant, 'enrollments.read'), false))) then
    raise exception 'not allowed to read enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectTypes', to_jsonb(x."subject_types"), 'steps', x."steps", 'enabled', x."enabled", 'archivedAt', x."archived_at", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."key")
    from "better_supabase"."enrollment_programs" x where x."tenant_id" = enrollment_programs.tenant
      and (coalesce(enrollment_programs.include_archived, false) or x."archived_at" is null)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_enrollment_program (
  program_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."enrollment_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."enrollment_programs" x where x."id" = purge_enrollment_program.program_id for update;
  if v_row."id" is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.manage'), false))) then
    raise exception 'not allowed to purge enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    raise exception 'archive the program before purging it' using errcode = '55000', hint = 'ENROLLMENTS_PROGRAM_NOT_ARCHIVED';
  end if;
  delete from "better_supabase"."enrollments" x where x."tenant_id" = v_row."tenant_id" and x."program" = v_row."key";
  delete from "better_supabase"."enrollment_programs" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('enrollment_program.purged', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version"), 'enrollment-programs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  perform better_supabase.audit_event(
    event_type => 'enrollment_program.purged',
    category => 'data',
    target_type => 'enrollment_program',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'purged an enrollment program',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_enrollment_program (
  program_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."enrollment_programs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."enrollment_programs" x where x."id" = restore_enrollment_program.program_id for update;
  if v_row."id" is null then
    raise exception 'enrollment program not found' using errcode = 'P0002', hint = 'ENROLLMENTS_PROGRAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.manage'), false))) then
    raise exception 'not allowed to manage enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectTypes', to_jsonb(v_row."subject_types"), 'steps', v_row."steps", 'enabled', v_row."enabled", 'archivedAt', v_row."archived_at", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."enrollment_programs" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('enrollment_program.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version"), 'enrollment-programs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  perform better_supabase.audit_event(
    event_type => 'enrollment_program.restored',
    category => 'data',
    target_type => 'enrollment_program',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'restored an enrollment program',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectTypes', to_jsonb(v_row."subject_types"), 'steps', v_row."steps", 'enabled', v_row."enabled", 'archivedAt', v_row."archived_at", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_enrollment_program (
  tenant  uuid,
  program jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
    if v_old."archived_at" is not null then
      raise exception 'program is archived; restore it first' using errcode = '55000', hint = 'ENROLLMENTS_PROGRAM_ARCHIVED';
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
    if jsonb_typeof(v_step -> 'assignee') is not null and jsonb_typeof(v_step -> 'assignee') <> 'null' then
      if jsonb_typeof(v_step -> 'assignee') <> 'object' then
        raise exception 'a step assignee is { role } with a lowercase role or { userId } with a user id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
      end if;
      if (select count(*) from jsonb_object_keys(v_step -> 'assignee')) <> 1
        or not (coalesce(v_step -> 'assignee' ->> 'role', '') ~ '^[a-z][a-z0-9_-]{0,62}$' or coalesce(v_step -> 'assignee' ->> 'userId', '') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
        raise exception 'a step assignee is { role } with a lowercase role or { userId } with a user id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
      end if;
    end if;
    if jsonb_typeof(v_step -> 'due') is not null and jsonb_typeof(v_step -> 'due') <> 'null' then
      if jsonb_typeof(v_step -> 'due') <> 'object' then
        raise exception 'a step due date is { days, from } with whole days from -3650 to 3650 and from "start" or "end"' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
      end if;
      if exists (select 1 from jsonb_object_keys(v_step -> 'due') as k(key) where k.key not in ('days', 'from'))
        or coalesce(v_step -> 'due' ->> 'from', '') not in ('start', 'end')
        or jsonb_typeof(v_step -> 'due' -> 'days') is distinct from 'number'
        or (case when (v_step -> 'due' ->> 'days') ~ '^-?[0-9]{1,4}$' then abs((v_step -> 'due' ->> 'days')::integer) > 3650 else true end) then
        raise exception 'a step due date is { days, from } with whole days from -3650 to 3650 and from "start" or "end"' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
      end if;
    end if;
    v_ids := v_ids || (v_step ->> 'id');
  end loop;
  v_steps := (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', t.value ->> 'id', 'title', t.value ->> 'title', 'description', t.value ->> 'description',
      'assignee', case when jsonb_typeof(t.value -> 'assignee') = 'object' then t.value -> 'assignee' end,
      'due', case when jsonb_typeof(t.value -> 'due') = 'object' then jsonb_build_object('days', (t.value -> 'due' ->> 'days')::integer, 'from', t.value -> 'due' ->> 'from') end)) order by t.ord)
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
  if v_old."id" is null then
    perform "better_supabase".emit_event('enrollment_program.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version"), 'enrollment-programs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  perform better_supabase.audit_event(
    event_type => 'enrollment_program.created',
    category => 'data',
    target_type => 'enrollment_program',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'created an enrollment program',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version")
  );
  else
    perform "better_supabase".emit_event('enrollment_program.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version"), 'enrollment-programs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  perform better_supabase.audit_event(
    event_type => 'enrollment_program.updated',
    category => 'data',
    target_type => 'enrollment_program',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'updated an enrollment program',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectTypes', to_jsonb(v_row."subject_types"), 'steps', v_row."steps", 'enabled', v_row."enabled", 'archivedAt', v_row."archived_at", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

REVOKE ALL ON FUNCTION "api"."archive_enrollment_program"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_enrollment_program"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."enrollment_programs"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."enrollment_programs"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_enrollment_program"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_enrollment_program"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_enrollment_program"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_enrollment_program"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_enrollment_program"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_enrollment_program"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."enrollment_programs"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."enrollment_programs"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_enrollment_program"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_enrollment_program"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_enrollment_program"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_enrollment_program"(uuid) TO "authenticated", "service_role";
