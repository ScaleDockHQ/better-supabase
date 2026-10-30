SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.enrollment_ensure (
  tenant          uuid,
  program         text,
  program_version integer,
  steps           text[],
  subject_type    text,
  subject_id      text,
  actor           uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."enrollments";
  v_was text;
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
    v_was := v_row."status";
    update "better_supabase"."enrollments" x set "steps" = enrollment_ensure.steps, "program_version" = enrollment_ensure.program_version
    where x."id" = v_row."id";
    update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps") and y."completed_at" is not null),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps") and y."completed_at" is not null) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps") and y."completed_at" is not null) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
    -- Removing the steps that were left can complete the enrollment.
    if v_was <> 'completed' and v_row."status" = 'completed' then
  if v_row."tenant_id" is not null then
    perform "better_supabase".emit_event('enrollment.completed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'program', v_row."program", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'step', null::text, 'completedSteps', v_row."completed_steps", 'totalSteps', cardinality(v_row."steps")), 'enrollments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  end if;
      null;
    end if;
  end if;
  return v_row."id";
end;
$function$;
