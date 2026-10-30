SET local check_function_bodies = off;

DROP FUNCTION "api"."update_employees"(jsonb);

DROP FUNCTION "better_supabase"."update_employees"(jsonb);

CREATE OR REPLACE FUNCTION api.delete_employee (
  employee uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_employee"($1) $function$;

CREATE OR REPLACE FUNCTION api.update_employees (
  changes jsonb,
  atomic  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_employees"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_employee (
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
  select * into v_row from "better_supabase"."employees" x where x."id" = delete_employee.employee for update;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'no such employee you can delete' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_delete"(uuid)');
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
  perform "better_supabase".emit_event('employee.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'userId', v_row."user_id"), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_delete"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$function$;

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
  perform "better_supabase".emit_event('employee.offboarded', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'userId', v_row."user_id", 'endDate', v_row."end_date", 'reason', v_row."offboard_reason"), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
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

CREATE OR REPLACE FUNCTION better_supabase.update_employees (
  changes jsonb,
  atomic  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_change jsonb;
  v_id uuid;
  v_field text;
  v_row "better_supabase"."employees";
  v_was "better_supabase"."employees";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_state text;
  v_touched uuid[] := '{}';
  v_seen jsonb := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_employees.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { employeeId, field, value }' using errcode = '22023', hint = 'EMPLOYEE_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_employees.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_id := (v_change ->> 'employeeId')::uuid;
      select * into v_was from "better_supabase"."employees" x where x."id" = v_id and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.write'), false)) for update;
      if v_was."id" is null then
        raise exception 'no such employee you can edit' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
      end if;
      if not v_seen ? v_id::text then
        v_seen := v_seen || jsonb_build_object(v_id::text, v_was."updated_at");
      end if;
      if v_change ? 'expectedUpdatedAt' and (v_seen ->> v_id::text)::timestamptz is distinct from (v_change ->> 'expectedUpdatedAt')::timestamptz then
        raise exception 'the employee changed since it was read' using errcode = '40001', hint = 'EMPLOYEE_STALE';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_id, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'name' then
        update "better_supabase"."employees" x set "name" = trim(v_change -> 'value' #>> '{}'), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'email' then
        update "better_supabase"."employees" x set "email" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'userId' then
        update "better_supabase"."employees" x set "user_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'jobTitle' then
        update "better_supabase"."employees" x set "job_title" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'teamId' then
        update "better_supabase"."employees" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'managerId' then
        update "better_supabase"."employees" x set "manager_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'employmentType' then
        update "better_supabase"."employees" x set "employment_type" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'startDate' then
        update "better_supabase"."employees" x set "start_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'endDate' then
        update "better_supabase"."employees" x set "end_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'status' then
        if (v_change ->> 'value') not in ('preboarding', 'active', 'on_leave') then
          raise exception 'status is preboarding, active or on_leave; offboard to end employment' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
        end if;
        update "better_supabase"."employees" x set "status" = v_change ->> 'value', "updated_at" = now() where x."id" = v_id returning * into v_row;
        if v_was."status" = 'offboarded' then
          update "better_supabase"."employees" x set "end_date" = null, "offboard_reason" = null where x."id" = v_id returning * into v_row;
  update "better_supabase"."employee_private_details" x set "offboarded_at" = null
  where x."employee_id" = v_id;
          null;
        end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'EMPLOYEE_FIELD_UNKNOWN';
      end case;
      if v_field = 'name' and nullif(v_row."name", '') is null then
        raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
      end if;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
      if v_field = 'userId' then
  if v_row."user_id" is not null and not exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
        null;
      end if;
      if v_row."manager_id" is distinct from v_was."manager_id" then
        perform "better_supabase".emit_event('employee.manager_changed', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'userId', v_row."user_id", 'fromManagerId', v_was."manager_id", 'toManagerId', v_row."manager_id"), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
      end if;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('employeeId', v_id, 'field', v_field));
      v_touched := array_append(v_touched, v_id);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_id, v_field;
    end if;
  end;
    exception when others then
      if update_employees.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text, v_state = returned_sqlstate;
      if v_state = '23505' then
        v_hint := 'EMPLOYEE_USER_TAKEN';
      elsif nullif(v_hint, '') is null and v_state in ('23514', '23502', '22P02', '22007', '22008') then
        v_hint := 'EMPLOYEE_ATTRS_INVALID';
      end if;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('employeeId', v_change ->> 'employeeId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."employees" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('employee.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'userId', v_row."user_id", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'employeeId')::uuid = v_row."id")), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."delete_employee"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_employee"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."update_employees"(jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_employees"(jsonb, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_employee"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_employee"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_employees"(jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_employees"(jsonb, boolean) TO "authenticated", "service_role";
