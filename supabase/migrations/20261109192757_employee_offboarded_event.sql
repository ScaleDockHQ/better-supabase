SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.offboard_employee (
  employee uuid,
  end_date date,
  reason   text
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
  select * into v_row from "better_supabase"."employees" x where x."id" = offboard_employee.employee;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'no such employee you can offboard' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if v_row."status" = 'offboarded' then
    return to_jsonb(v_row);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  begin
    update "better_supabase"."employees" x set "status" = 'offboarded', "end_date" = coalesce(offboard_employee.end_date, current_date), "offboard_reason" = nullif(trim(offboard_employee.reason), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation then
    raise exception 'the end date is before the start date' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;

  for v_report in select * from "better_supabase"."employees" x where x."manager_id" = v_row."id" loop
    update "better_supabase"."employees" x set "manager_id" = v_row."manager_id", "updated_at" = now()
    where x."id" = v_report."id"
    returning * into v_report;
    perform "better_supabase".emit_event('employee.manager_changed', jsonb_build_object('organizationId', v_report."tenant_id", 'employeeId', v_report."id", 'subjectType', 'employee', 'subjectId', v_report."id"::text, 'name', v_report."name", 'userId', v_report."user_id", 'fromManagerId', v_row."id", 'toManagerId', v_report."manager_id"), 'employees/' || v_report."id"::text, (v_report."tenant_id"::text)::text, null, 'better-supabase/employees');
  end loop;
  update "better_supabase"."employee_private_details" x set "offboarded_at" = now()
  where x."employee_id" = v_row."id";
  perform "better_supabase".emit_event('employee.offboarded', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'userId', v_row."user_id", 'endDate', v_row."end_date"), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$function$;
