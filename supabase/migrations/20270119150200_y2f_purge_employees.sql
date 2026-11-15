SET local check_function_bodies = off;

DROP FUNCTION "api"."delete_employee"(uuid);

DROP FUNCTION "better_supabase"."delete_employee"(uuid);

CREATE OR REPLACE FUNCTION api.purge_employee (
  employee uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_employee"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_employee (
  employee uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."employees";
  v_report "better_supabase"."employees";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."employees" x where x."id" = purge_employee.employee for update;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'no such employee you can purge' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'not allowed to purge employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  for v_report in select * from "better_supabase"."employees" x where x."manager_id" = v_row."id" loop
    update "better_supabase"."employees" x set "manager_id" = v_row."manager_id", "updated_at" = now()
    where x."id" = v_report."id"
    returning * into v_report;
    perform "better_supabase".emit_event('employee.manager_changed', jsonb_build_object('organizationId', v_report."tenant_id", 'employeeId', v_report."id", 'subjectType', 'employee', 'subjectId', v_report."id"::text, 'name', v_report."name", 'userId', v_report."user_id", 'fromManagerId', v_row."id", 'toManagerId', v_report."manager_id"), 'employees/' || v_report."id"::text, (v_report."tenant_id"::text)::text, null, 'better-supabase/employees');
  end loop;
  begin
    delete from "better_supabase"."employees" x where x."id" = v_row."id";
  exception when foreign_key_violation then
    raise exception 'other records still refer to this employee' using errcode = '23503', hint = 'EMPLOYEE_IN_USE';
  end;
  perform "better_supabase".emit_event('employee.purged', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'userId', v_row."user_id"), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_purge"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."purge_employee"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_employee"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_employee"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_employee"(uuid) TO "authenticated", "service_role";
