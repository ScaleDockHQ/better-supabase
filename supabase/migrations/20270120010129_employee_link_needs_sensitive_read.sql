SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.create_employee (
  tenant uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."employees";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_employee.tenant, 'employees.write'), false)) then
    raise exception 'not allowed to change employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  if create_employee.attrs -> 'origin' ->> 'id' is not null then
    select * into v_row from "better_supabase"."employees" x
    where x."tenant_id" = create_employee.tenant
      and x."origin_type" = create_employee.attrs -> 'origin' ->> 'type'
      and x."origin_id" = create_employee.attrs -> 'origin' ->> 'id';
    if v_row."id" is not null then
      return to_jsonb(v_row);
    end if;
  end if;
  if nullif(trim(create_employee.attrs ->> 'name'), '') is null then
    raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_employee.tenant, create_employee.attrs;
    end if;
  end;
  begin
    v_status := coalesce(create_employee.attrs ->> 'status', case when (create_employee.attrs ->> 'startDate')::date > current_date then 'preboarding' else 'active' end);
    if v_status = 'offboarded' then
      raise exception 'create the employee, then offboard them' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
    end if;
    insert into "better_supabase"."employees" ("tenant_id", "name", "email", "user_id", "job_title", "team_id", "manager_id", "employment_type", "start_date", "end_date", "status", "origin_type", "origin_id", "created_by")
    values (create_employee.tenant, trim(create_employee.attrs -> 'name' #>> '{}'), nullif(trim(create_employee.attrs -> 'email' #>> '{}'), ''), (create_employee.attrs -> 'userId' #>> '{}')::uuid, nullif(trim(create_employee.attrs -> 'jobTitle' #>> '{}'), ''), (create_employee.attrs -> 'teamId' #>> '{}')::uuid, (create_employee.attrs -> 'managerId' #>> '{}')::uuid, coalesce(nullif(trim(create_employee.attrs -> 'employmentType' #>> '{}'), ''), (array['employee', 'contractor', 'intern', 'temporary']::text[])[1]), (create_employee.attrs -> 'startDate' #>> '{}')::date, (create_employee.attrs -> 'endDate' #>> '{}')::date, v_status, create_employee.attrs -> 'origin' ->> 'type', create_employee.attrs -> 'origin' ->> 'id', auth.uid())
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'that user is already an employee of this organization' using errcode = '23505', hint = 'EMPLOYEE_USER_TAKEN';
    when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'an employee field has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
  if v_row."user_id" is not null and not exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
  if v_row."user_id" is not null and not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'linking an employee to an account needs the sensitive read permission' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  if v_row."origin_id" is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'employee', v_row."id"::text, v_row."origin_type", v_row."origin_id", auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'employee' and x."source_id" = v_row."id"::text
    );
  end if;
  perform "better_supabase".emit_event('employee.created', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'userId', v_row."user_id", 'managerId', v_row."manager_id", 'status', v_row."status"), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_create"(uuid)');
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
        if v_row."user_id" is distinct from v_was."user_id" then
  if v_row."user_id" is not null and not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'linking an employee to an account needs the sensitive read permission' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
        end if;
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


CREATE OR REPLACE FUNCTION better_supabase.create_employee (
  tenant uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."employees";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_employee.tenant, 'employees.write'), false)) then
    raise exception 'not allowed to change employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  if create_employee.attrs -> 'origin' ->> 'id' is not null then
    select * into v_row from "better_supabase"."employees" x
    where x."tenant_id" = create_employee.tenant
      and x."origin_type" = create_employee.attrs -> 'origin' ->> 'type'
      and x."origin_id" = create_employee.attrs -> 'origin' ->> 'id';
    if v_row."id" is not null then
      return to_jsonb(v_row);
    end if;
  end if;
  if nullif(trim(create_employee.attrs ->> 'name'), '') is null then
    raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_employee.tenant, create_employee.attrs;
    end if;
  end;
  begin
    v_status := coalesce(create_employee.attrs ->> 'status', case when (create_employee.attrs ->> 'startDate')::date > current_date then 'preboarding' else 'active' end);
    if v_status = 'offboarded' then
      raise exception 'create the employee, then offboard them' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
    end if;
    insert into "better_supabase"."employees" ("tenant_id", "name", "email", "user_id", "job_title", "team_id", "manager_id", "employment_type", "start_date", "end_date", "status", "origin_type", "origin_id", "created_by")
    values (create_employee.tenant, trim(create_employee.attrs -> 'name' #>> '{}'), nullif(trim(create_employee.attrs -> 'email' #>> '{}'), ''), (create_employee.attrs -> 'userId' #>> '{}')::uuid, nullif(trim(create_employee.attrs -> 'jobTitle' #>> '{}'), ''), (create_employee.attrs -> 'teamId' #>> '{}')::uuid, (create_employee.attrs -> 'managerId' #>> '{}')::uuid, coalesce(nullif(trim(create_employee.attrs -> 'employmentType' #>> '{}'), ''), (array['employee', 'contractor', 'intern', 'temporary']::text[])[1]), (create_employee.attrs -> 'startDate' #>> '{}')::date, (create_employee.attrs -> 'endDate' #>> '{}')::date, v_status, create_employee.attrs -> 'origin' ->> 'type', create_employee.attrs -> 'origin' ->> 'id', auth.uid())
    returning * into v_row;
  exception
    when unique_violation then
      raise exception 'that user is already an employee of this organization' using errcode = '23505', hint = 'EMPLOYEE_USER_TAKEN';
    when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'an employee field has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
  if v_row."user_id" is not null and not exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
  if v_row."user_id" is not null and not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'linking an employee to an account needs the sensitive read permission' using errcode = '42501', hint = 'EMPLOYEE_LINK_FORBIDDEN';
  end if;
  if v_row."origin_id" is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'employee', v_row."id"::text, v_row."origin_type", v_row."origin_id", auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'employee' and x."source_id" = v_row."id"::text
    );
  end if;
  perform "better_supabase".emit_event('employee.created', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'userId', v_row."user_id", 'managerId', v_row."manager_id", 'status', v_row."status"), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_create"(uuid)');
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
        if v_row."user_id" is distinct from v_was."user_id" then
  if v_row."user_id" is not null and not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read_sensitive'), false))) then
    raise exception 'linking an employee to an account needs the sensitive read permission' using errcode = '42501', hint = 'EMPLOYEE_LINK_FORBIDDEN';
  end if;
        end if;
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
