SET local check_function_bodies = off;

DROP FUNCTION "api"."delete_maintenance_plan"(uuid);

DROP FUNCTION "better_supabase"."delete_maintenance_plan"(uuid);

ALTER TABLE "better_supabase"."maintenance_plans"
  ADD COLUMN "archived_at" timestamp WITH time zone;

CREATE OR REPLACE FUNCTION api.archive_maintenance_plan (
  plan_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_maintenance_plan"($1) $function$;

CREATE OR REPLACE FUNCTION api.purge_maintenance_plan (
  plan_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_maintenance_plan"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_maintenance_plan (
  plan_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_maintenance_plan"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_maintenance_plan (
  plan_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."maintenance_plans";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_plans" x where x."id" = archive_maintenance_plan.plan_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'maintenance.read'), false))) then
    raise exception 'no such maintenance plan' using errcode = 'P0002', hint = 'MAINTENANCE_PLAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'maintenance.manage'), false))) then
    raise exception 'not allowed to manage maintenance plans' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'kind', v_row."kind", 'assetId', v_row."asset_id", 'everyDays', v_row."every_days", 'meterId', v_row."meter_id", 'everyValue', v_row."every_value"::text, 'priority', v_row."priority", 'status', v_row."status", 'lastDoneAt', v_row."last_done_at", 'lastDoneValue', v_row."last_done_value"::text, 'nextDueAt', v_row."next_due_at", 'workOrderId', v_row."work_order_id", 'rrule', v_row."rrule", 'dtstart', v_row."dtstart", 'tz', v_row."tz", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."maintenance_plans" x set
    "archived_at" = now(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('maintenance_plan.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'title', v_row."title", 'kind', v_row."kind", 'status', v_row."status"), 'maintenance-plans/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/maintenance');
  perform better_supabase.audit_event(
    event_type => 'maintenance_plan.archived',
    category => 'data',
    target_type => 'maintenance_plan',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'maintenance plan archived',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'title', v_row."title", 'kind', v_row."kind", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'kind', v_row."kind", 'assetId', v_row."asset_id", 'everyDays', v_row."every_days", 'meterId', v_row."meter_id", 'everyValue', v_row."every_value"::text, 'priority', v_row."priority", 'status', v_row."status", 'lastDoneAt', v_row."last_done_at", 'lastDoneValue', v_row."last_done_value"::text, 'nextDueAt', v_row."next_due_at", 'workOrderId', v_row."work_order_id", 'rrule', v_row."rrule", 'dtstart', v_row."dtstart", 'tz', v_row."tz", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_maintenance_plan (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."maintenance_plans";
  v_title text;
  v_kind text;
  v_days integer;
  v_value numeric;
  v_meter uuid;
  v_asset uuid;
  v_priority text;
  v_rrule text;
  v_dtstart timestamptz;
  v_tz text;
  v_required text[] := '{}';
  v_reading numeric;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_maintenance_plan.tenant is not null and coalesce(better_supabase.can('tenant', create_maintenance_plan.tenant, 'maintenance.manage'), false))) then
    raise exception 'not allowed to manage maintenance plans' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  if jsonb_typeof(create_maintenance_plan.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  begin
    v_title := trim(create_maintenance_plan.input ->> 'title');
    v_kind := create_maintenance_plan.input ->> 'kind';
    v_days := (create_maintenance_plan.input ->> 'everyDays')::integer;
    v_value := (create_maintenance_plan.input ->> 'everyValue')::numeric;
    v_meter := nullif(create_maintenance_plan.input ->> 'meterId', '')::uuid;
    v_asset := nullif(create_maintenance_plan.input ->> 'assetId', '')::uuid;
    v_priority := coalesce(nullif(create_maintenance_plan.input ->> 'priority', ''), 'normal');
    v_rrule := nullif(trim(create_maintenance_plan.input ->> 'rrule'), '');
    v_dtstart := (create_maintenance_plan.input ->> 'dtstart')::timestamptz;
    v_tz := coalesce(nullif(trim(create_maintenance_plan.input ->> 'tz'), ''), 'UTC');
    if create_maintenance_plan.input ? 'requiredQualifications' then
      if jsonb_typeof(create_maintenance_plan.input -> 'requiredQualifications') is distinct from 'array' then
        raise exception 'requiredQualifications is a list of qualification type keys' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
      end if;
      select coalesce(array_agg(distinct k), '{}') into v_required from jsonb_array_elements_text(create_maintenance_plan.input -> 'requiredQualifications') k;
    end if;
  exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow or invalid_parameter_value then
    raise exception 'everyDays and everyValue are numbers, meterId and assetId are ids, dtstart is a timestamp and requiredQualifications holds keys' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    raise exception 'a plan needs a title of 1 to 200 characters' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_kind = 'time' and (v_days is null or v_days < 1 or v_meter is not null or v_value is not null) then
    raise exception 'a time plan needs everyDays of at least 1 and no meter' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_kind = 'meter' and (v_meter is null or v_value is null or v_value <= 0 or v_days is not null) then
    raise exception 'a meter plan needs a meterId and an everyValue above 0' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_kind = 'rrule' and (v_rrule is null or v_dtstart is null or v_days is not null or v_meter is not null or v_value is not null) then
    raise exception 'a calendar plan needs an rrule and a dtstart, and no everyDays or meter' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_kind in ('time', 'meter') and (v_rrule is not null or v_dtstart is not null) then
    raise exception 'only a plan of kind rrule takes an rrule and a dtstart' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_kind = 'rrule' and (length(v_rrule) > 500 or v_rrule !~* '(^|[:;])FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)(;|$)') then
    raise exception 'the rrule needs FREQ of DAILY, WEEKLY, MONTHLY or YEARLY and at most 500 characters' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_kind = 'rrule' and not exists (select 1 from pg_catalog.pg_timezone_names n where n.name = v_tz) then
    raise exception 'tz is an IANA time zone name' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_kind is null or v_kind not in ('time', 'meter', 'rrule') then
    raise exception 'the kind is time, meter or rrule' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if exists (
    select 1 from unnest(v_required) k
    where not exists (
      select 1 from "better_supabase"."qualification_types" o
      where o."tenant_id" = create_maintenance_plan.tenant and o."key" = k and o."archived_at" is null
    )
  ) then
    raise exception 'every required qualification is a qualification type key of this organization' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_priority not in ('low', 'normal', 'high', 'urgent') then
    raise exception 'the priority is low, normal, high or urgent' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_meter is not null then
    select z."reading" into v_reading from "better_supabase"."maintenance_meters" z
    where z."id" = v_meter and z."tenant_id" = create_maintenance_plan.tenant;
    if not found then
      raise exception 'no such meter' using errcode = 'P0002', hint = 'MAINTENANCE_METER_NOT_FOUND';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_maintenance_plan_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_maintenance_plan.tenant, create_maintenance_plan.input;
    end if;
  end;
  begin
    insert into "better_supabase"."maintenance_plans" ("tenant_id", "title", "asset_id", "kind", "every_days", "meter_id", "every_value", "priority", "last_done_value", "rrule", "dtstart", "tz", "required_qualifications", "next_due_at", "created_by")
    values (create_maintenance_plan.tenant, v_title, v_asset, v_kind, v_days, v_meter, v_value, v_priority, v_reading,
      v_rrule, v_dtstart, v_tz, v_required,
      case v_kind
        when 'time' then now() + v_days * interval '1 day'
        when 'rrule' then "better_supabase"."maintenance_next_occurrence"(v_dtstart, v_tz, v_rrule, now())
      end, auth.uid())
    returning * into v_row;
  if create_maintenance_plan.input ? 'parts' then
    if jsonb_typeof(create_maintenance_plan.input -> 'parts') is distinct from 'array' then
      raise exception 'parts must be a list' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
    end if;
    delete from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = v_row."id";
    insert into "better_supabase"."maintenance_plan_parts" ("tenant_id", "plan_id", "name", "quantity", "variant_id")
    select v_row."tenant_id", v_row."id", trim(e ->> 'name'), coalesce((e ->> 'quantity')::numeric, 1), nullif(e ->> 'variantId', '')::uuid
    from jsonb_array_elements(create_maintenance_plan.input -> 'parts') e;
  end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a part needs a name of 1 to 200 characters and a quantity above 0' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end;
  perform "better_supabase".emit_event('maintenance_plan.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'title', v_row."title", 'kind', v_row."kind", 'status', v_row."status"), 'maintenance-plans/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/maintenance');
  perform better_supabase.audit_event(
    event_type => 'maintenance_plan.created',
    category => 'data',
    target_type => 'maintenance_plan',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'maintenance plan created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'title', v_row."title", 'kind', v_row."kind", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_maintenance_plan_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'kind', v_row."kind", 'assetId', v_row."asset_id", 'everyDays', v_row."every_days", 'meterId', v_row."meter_id", 'everyValue', v_row."every_value"::text, 'priority', v_row."priority", 'status', v_row."status", 'lastDoneAt', v_row."last_done_at", 'lastDoneValue', v_row."last_done_value"::text, 'nextDueAt', v_row."next_due_at", 'workOrderId', v_row."work_order_id", 'rrule', v_row."rrule", 'dtstart', v_row."dtstart", 'tz', v_row."tz", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'due', v_row."status" = 'active' and v_row."archived_at" is null and v_row."work_order_id" is null and (
      (v_row."kind" in ('time', 'rrule') and v_row."next_due_at" <= now())
      or (v_row."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = v_row."meter_id" and z."reading" >= coalesce(v_row."last_done_value", 0) + v_row."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = v_row."id"
    ), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.generate_maintenance_work_orders (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_plan "better_supabase"."maintenance_plans";
  v_view jsonb;
  v_order jsonb;
  v_part record;
  v_made jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (generate_maintenance_work_orders.tenant is not null and coalesce(better_supabase.can('tenant', generate_maintenance_work_orders.tenant, 'maintenance.manage'), false))) then
    raise exception 'not allowed to manage maintenance plans' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  for v_plan in
    select * from "better_supabase"."maintenance_plans" x
    where x."tenant_id" = generate_maintenance_work_orders.tenant and x."status" = 'active' and x."archived_at" is null and x."work_order_id" is null
    order by x."next_due_at" nulls last, x."id"
    for update
  loop
    v_view := jsonb_build_object('id', v_plan."id", 'organizationId', v_plan."tenant_id", 'title', v_plan."title", 'kind', v_plan."kind", 'assetId', v_plan."asset_id", 'everyDays', v_plan."every_days", 'meterId', v_plan."meter_id", 'everyValue', v_plan."every_value"::text, 'priority', v_plan."priority", 'status', v_plan."status", 'lastDoneAt', v_plan."last_done_at", 'lastDoneValue', v_plan."last_done_value"::text, 'nextDueAt', v_plan."next_due_at", 'workOrderId', v_plan."work_order_id", 'rrule', v_plan."rrule", 'dtstart', v_plan."dtstart", 'tz', v_plan."tz", 'requiredQualifications', to_jsonb(v_plan."required_qualifications"), 'archivedAt', v_plan."archived_at", 'createdAt', v_plan."created_at", 'updatedAt', v_plan."updated_at") || jsonb_build_object(
    'due', v_plan."status" = 'active' and v_plan."archived_at" is null and v_plan."work_order_id" is null and (
      (v_plan."kind" in ('time', 'rrule') and v_plan."next_due_at" <= now())
      or (v_plan."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = v_plan."meter_id" and z."reading" >= coalesce(v_plan."last_done_value", 0) + v_plan."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = v_plan."id"
    ), '[]'::jsonb));
    continue when not (v_view ->> 'due')::boolean;
    v_order := "better_supabase"."create_work_order"(
      tenant => v_plan."tenant_id",
      title => v_plan."title",
      priority => v_plan."priority",
      asset_id => v_plan."asset_id");
    for v_part in
      select y."name" as name, y."quantity" as quantity, y."variant_id" as variant
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = v_plan."id" order by y."name", y."id"
    loop
      perform "better_supabase"."record_work_order_part"(
        work_order_id => (v_order ->> 'id')::uuid,
        name => v_part.name,
        quantity => v_part.quantity,
        asset_id => v_plan."asset_id",
        variant_id => v_part.variant);
    end loop;
    update "better_supabase"."maintenance_plans" x set "work_order_id" = (v_order ->> 'id')::uuid, "updated_at" = now()
    where x."id" = v_plan."id"
    returning * into v_plan;
    perform "better_supabase".emit_event('maintenance_plan.triggered', jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'title', v_plan."title", 'kind', v_plan."kind", 'status', v_plan."status", 'workOrderId', v_plan."work_order_id"), 'maintenance-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/maintenance');
  perform better_supabase.audit_event(
    event_type => 'maintenance_plan.triggered',
    category => 'data',
    target_type => 'maintenance_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."title",
    summary => 'maintenance work order opened',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'title', v_plan."title", 'kind', v_plan."kind", 'status', v_plan."status", 'workOrderId', v_plan."work_order_id")
  );
    v_made := v_made || jsonb_build_array(jsonb_build_object('planId', v_plan."id", 'workOrderId', v_plan."work_order_id"));
  end loop;
  return v_made;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_maintenance_plan (
  plan_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."maintenance_plans";
begin
  select * into v_row from "better_supabase"."maintenance_plans" x where x."id" = get_maintenance_plan.plan_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'maintenance.read'), false))) then
    raise exception 'no such maintenance plan' using errcode = 'P0002', hint = 'MAINTENANCE_PLAN_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'kind', v_row."kind", 'assetId', v_row."asset_id", 'everyDays', v_row."every_days", 'meterId', v_row."meter_id", 'everyValue', v_row."every_value"::text, 'priority', v_row."priority", 'status', v_row."status", 'lastDoneAt', v_row."last_done_at", 'lastDoneValue', v_row."last_done_value"::text, 'nextDueAt', v_row."next_due_at", 'workOrderId', v_row."work_order_id", 'rrule', v_row."rrule", 'dtstart', v_row."dtstart", 'tz', v_row."tz", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'due', v_row."status" = 'active' and v_row."archived_at" is null and v_row."work_order_id" is null and (
      (v_row."kind" in ('time', 'rrule') and v_row."next_due_at" <= now())
      or (v_row."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = v_row."meter_id" and z."reading" >= coalesce(v_row."last_done_value", 0) + v_row."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = v_row."id"
    ), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_maintenance_plans (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_maintenance_plans.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_maintenance_plans.tenant is not null and coalesce(better_supabase.can('tenant', list_maintenance_plans.tenant, 'maintenance.read'), false))) then
    raise exception 'not allowed to read maintenance' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'kind') then
      raise exception 'facet is one of status, kind' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'kind' then (x."kind")::text end) as v
      from "better_supabase"."maintenance_plans" x
      where x."tenant_id" = list_maintenance_plans.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
    'due', x."status" = 'active' and x."archived_at" is null and x."work_order_id" is null and (
      (x."kind" in ('time', 'rrule') and x."next_due_at" <= now())
      or (x."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = x."meter_id" and z."reading" >= coalesce(x."last_done_value", 0) + x."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = x."id"
    ), '[]'::jsonb)) ->> 'due')::boolean)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."maintenance_plans" x
      where x."tenant_id" = list_maintenance_plans.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
    'due', x."status" = 'active' and x."archived_at" is null and x."work_order_id" is null and (
      (x."kind" in ('time', 'rrule') and x."next_due_at" <= now())
      or (x."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = x."meter_id" and z."reading" >= coalesce(x."last_done_value", 0) + x."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = x."id"
    ), '[]'::jsonb)) ->> 'due')::boolean)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('nextDueAt', 'title') then
    raise exception 'sort is one of nextDueAt, title' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
    'due', x."status" = 'active' and x."archived_at" is null and x."work_order_id" is null and (
      (x."kind" in ('time', 'rrule') and x."next_due_at" <= now())
      or (x."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = x."meter_id" and z."reading" >= coalesce(x."last_done_value", 0) + x."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = x."id"
    ), '[]'::jsonb)) as j, jsonb_build_array((coalesce(x."next_due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_plans" x
      where x."tenant_id" = list_maintenance_plans.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
    'due', x."status" = 'active' and x."archived_at" is null and x."work_order_id" is null and (
      (x."kind" in ('time', 'rrule') and x."next_due_at" <= now())
      or (x."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = x."meter_id" and z."reading" >= coalesce(x."last_done_value", 0) + x."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = x."id"
    ), '[]'::jsonb)) ->> 'due')::boolean)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_after is null or (coalesce(x."next_due_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."next_due_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
    'due', x."status" = 'active' and x."archived_at" is null and x."work_order_id" is null and (
      (x."kind" in ('time', 'rrule') and x."next_due_at" <= now())
      or (x."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = x."meter_id" and z."reading" >= coalesce(x."last_done_value", 0) + x."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = x."id"
    ), '[]'::jsonb)) as j, jsonb_build_array((coalesce(x."next_due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_plans" x
      where x."tenant_id" = list_maintenance_plans.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
    'due', x."status" = 'active' and x."archived_at" is null and x."work_order_id" is null and (
      (x."kind" in ('time', 'rrule') and x."next_due_at" <= now())
      or (x."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = x."meter_id" and z."reading" >= coalesce(x."last_done_value", 0) + x."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = x."id"
    ), '[]'::jsonb)) ->> 'due')::boolean)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_after is null or (coalesce(x."next_due_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."next_due_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."next_due_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."next_due_at", 'infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'nextDueAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
    'due', x."status" = 'active' and x."archived_at" is null and x."work_order_id" is null and (
      (x."kind" in ('time', 'rrule') and x."next_due_at" <= now())
      or (x."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = x."meter_id" and z."reading" >= coalesce(x."last_done_value", 0) + x."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = x."id"
    ), '[]'::jsonb)) as j, jsonb_build_array((coalesce(x."next_due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_plans" x
      where x."tenant_id" = list_maintenance_plans.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
    'due', x."status" = 'active' and x."archived_at" is null and x."work_order_id" is null and (
      (x."kind" in ('time', 'rrule') and x."next_due_at" <= now())
      or (x."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = x."meter_id" and z."reading" >= coalesce(x."last_done_value", 0) + x."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = x."id"
    ), '[]'::jsonb)) ->> 'due')::boolean)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_after is null or (coalesce(x."next_due_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."next_due_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'nextDueAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
    'due', x."status" = 'active' and x."archived_at" is null and x."work_order_id" is null and (
      (x."kind" in ('time', 'rrule') and x."next_due_at" <= now())
      or (x."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = x."meter_id" and z."reading" >= coalesce(x."last_done_value", 0) + x."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = x."id"
    ), '[]'::jsonb)) as j, jsonb_build_array((coalesce(x."next_due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_plans" x
      where x."tenant_id" = list_maintenance_plans.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
    'due', x."status" = 'active' and x."archived_at" is null and x."work_order_id" is null and (
      (x."kind" in ('time', 'rrule') and x."next_due_at" <= now())
      or (x."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = x."meter_id" and z."reading" >= coalesce(x."last_done_value", 0) + x."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = x."id"
    ), '[]'::jsonb)) ->> 'due')::boolean)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_after is null or (coalesce(x."next_due_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."next_due_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."next_due_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."next_due_at", 'infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
    'due', x."status" = 'active' and x."archived_at" is null and x."work_order_id" is null and (
      (x."kind" in ('time', 'rrule') and x."next_due_at" <= now())
      or (x."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = x."meter_id" and z."reading" >= coalesce(x."last_done_value", 0) + x."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = x."id"
    ), '[]'::jsonb)) as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_plans" x
      where x."tenant_id" = list_maintenance_plans.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
    'due', x."status" = 'active' and x."archived_at" is null and x."work_order_id" is null and (
      (x."kind" in ('time', 'rrule') and x."next_due_at" <= now())
      or (x."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = x."meter_id" and z."reading" >= coalesce(x."last_done_value", 0) + x."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = x."id"
    ), '[]'::jsonb)) ->> 'due')::boolean)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_after is null or (x."title", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."title" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
    'due', x."status" = 'active' and x."archived_at" is null and x."work_order_id" is null and (
      (x."kind" in ('time', 'rrule') and x."next_due_at" <= now())
      or (x."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = x."meter_id" and z."reading" >= coalesce(x."last_done_value", 0) + x."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = x."id"
    ), '[]'::jsonb)) as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_plans" x
      where x."tenant_id" = list_maintenance_plans.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
    'due', x."status" = 'active' and x."archived_at" is null and x."work_order_id" is null and (
      (x."kind" in ('time', 'rrule') and x."next_due_at" <= now())
      or (x."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = x."meter_id" and z."reading" >= coalesce(x."last_done_value", 0) + x."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = x."id"
    ), '[]'::jsonb)) ->> 'due')::boolean)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_after is null or (x."title" <= (v_after ->> 0)::text and ((x."title" < (v_after ->> 0)::text) or (x."title" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."title" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."maintenance_plans" x
      where x."tenant_id" = list_maintenance_plans.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
    'due', x."status" = 'active' and x."archived_at" is null and x."work_order_id" is null and (
      (x."kind" in ('time', 'rrule') and x."next_due_at" <= now())
      or (x."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = x."meter_id" and z."reading" >= coalesce(x."last_done_value", 0) + x."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = x."id"
    ), '[]'::jsonb)) ->> 'due')::boolean)
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_maintenance_plan (
  plan_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."maintenance_plans";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_plans" x where x."id" = purge_maintenance_plan.plan_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'maintenance.read'), false))) then
    raise exception 'no such maintenance plan' using errcode = 'P0002', hint = 'MAINTENANCE_PLAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'maintenance.manage'), false))) then
    raise exception 'not allowed to manage maintenance plans' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  delete from "better_supabase"."maintenance_plans" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('maintenance_plan.purged', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'title', v_row."title", 'kind', v_row."kind", 'status', v_row."status"), 'maintenance-plans/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/maintenance');
  perform better_supabase.audit_event(
    event_type => 'maintenance_plan.purged',
    category => 'data',
    target_type => 'maintenance_plan',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'maintenance plan purged',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'title', v_row."title", 'kind', v_row."kind", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'kind', v_row."kind", 'assetId', v_row."asset_id", 'everyDays', v_row."every_days", 'meterId', v_row."meter_id", 'everyValue', v_row."every_value"::text, 'priority', v_row."priority", 'status', v_row."status", 'lastDoneAt', v_row."last_done_at", 'lastDoneValue', v_row."last_done_value"::text, 'nextDueAt', v_row."next_due_at", 'workOrderId', v_row."work_order_id", 'rrule', v_row."rrule", 'dtstart', v_row."dtstart", 'tz', v_row."tz", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_maintenance_plan (
  plan_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."maintenance_plans";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_plans" x where x."id" = restore_maintenance_plan.plan_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'maintenance.read'), false))) then
    raise exception 'no such maintenance plan' using errcode = 'P0002', hint = 'MAINTENANCE_PLAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'maintenance.manage'), false))) then
    raise exception 'not allowed to manage maintenance plans' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'kind', v_row."kind", 'assetId', v_row."asset_id", 'everyDays', v_row."every_days", 'meterId', v_row."meter_id", 'everyValue', v_row."every_value"::text, 'priority', v_row."priority", 'status', v_row."status", 'lastDoneAt', v_row."last_done_at", 'lastDoneValue', v_row."last_done_value"::text, 'nextDueAt', v_row."next_due_at", 'workOrderId', v_row."work_order_id", 'rrule', v_row."rrule", 'dtstart', v_row."dtstart", 'tz', v_row."tz", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."maintenance_plans" x set
    "archived_at" = null,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('maintenance_plan.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'title', v_row."title", 'kind', v_row."kind", 'status', v_row."status"), 'maintenance-plans/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/maintenance');
  perform better_supabase.audit_event(
    event_type => 'maintenance_plan.restored',
    category => 'data',
    target_type => 'maintenance_plan',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'maintenance plan restored',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'title', v_row."title", 'kind', v_row."kind", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'kind', v_row."kind", 'assetId', v_row."asset_id", 'everyDays', v_row."every_days", 'meterId', v_row."meter_id", 'everyValue', v_row."every_value"::text, 'priority', v_row."priority", 'status', v_row."status", 'lastDoneAt', v_row."last_done_at", 'lastDoneValue', v_row."last_done_value"::text, 'nextDueAt', v_row."next_due_at", 'workOrderId', v_row."work_order_id", 'rrule', v_row."rrule", 'dtstart', v_row."dtstart", 'tz', v_row."tz", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_maintenance_plan (
  plan_id uuid,
  changes jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."maintenance_plans";
  v_title text;
  v_kind text;
  v_days integer;
  v_value numeric;
  v_meter uuid;
  v_asset uuid;
  v_priority text;
  v_rrule text;
  v_dtstart timestamptz;
  v_tz text;
  v_required text[];
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_plans" x where x."id" = update_maintenance_plan.plan_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'maintenance.read'), false))) then
    raise exception 'no such maintenance plan' using errcode = 'P0002', hint = 'MAINTENANCE_PLAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'maintenance.manage'), false))) then
    raise exception 'not allowed to manage maintenance plans' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  if jsonb_typeof(update_maintenance_plan.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if update_maintenance_plan.changes ? 'kind' or update_maintenance_plan.changes ? 'meterId' then
    raise exception 'a plan keeps its kind and meter' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  begin
    v_title := trim(update_maintenance_plan.changes ->> 'title');
    v_kind := update_maintenance_plan.changes ->> 'kind';
    v_days := (update_maintenance_plan.changes ->> 'everyDays')::integer;
    v_value := (update_maintenance_plan.changes ->> 'everyValue')::numeric;
    v_meter := nullif(update_maintenance_plan.changes ->> 'meterId', '')::uuid;
    v_asset := nullif(update_maintenance_plan.changes ->> 'assetId', '')::uuid;
    v_priority := coalesce(nullif(update_maintenance_plan.changes ->> 'priority', ''), 'normal');
    v_rrule := nullif(trim(update_maintenance_plan.changes ->> 'rrule'), '');
    v_dtstart := (update_maintenance_plan.changes ->> 'dtstart')::timestamptz;
    v_tz := coalesce(nullif(trim(update_maintenance_plan.changes ->> 'tz'), ''), 'UTC');
    if update_maintenance_plan.changes ? 'requiredQualifications' then
      if jsonb_typeof(update_maintenance_plan.changes -> 'requiredQualifications') is distinct from 'array' then
        raise exception 'requiredQualifications is a list of qualification type keys' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
      end if;
      select coalesce(array_agg(distinct k), '{}') into v_required from jsonb_array_elements_text(update_maintenance_plan.changes -> 'requiredQualifications') k;
    end if;
  exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow or invalid_parameter_value then
    raise exception 'everyDays and everyValue are numbers, meterId and assetId are ids, dtstart is a timestamp and requiredQualifications holds keys' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end;
  v_kind := v_row."kind";
  v_meter := v_row."meter_id";
  v_title := case when update_maintenance_plan.changes ? 'title' then v_title else v_row."title" end;
  v_days := case when update_maintenance_plan.changes ? 'everyDays' then v_days else v_row."every_days" end;
  v_value := case when update_maintenance_plan.changes ? 'everyValue' then v_value else v_row."every_value" end;
  v_asset := case when update_maintenance_plan.changes ? 'assetId' then v_asset else v_row."asset_id" end;
  v_priority := case when update_maintenance_plan.changes ? 'priority' then v_priority else v_row."priority" end;
  v_rrule := case when update_maintenance_plan.changes ? 'rrule' then v_rrule else v_row."rrule" end;
  v_dtstart := case when update_maintenance_plan.changes ? 'dtstart' then v_dtstart else v_row."dtstart" end;
  v_tz := case when update_maintenance_plan.changes ? 'tz' then v_tz else v_row."tz" end;
  v_required := case when update_maintenance_plan.changes ? 'requiredQualifications' then v_required else v_row."required_qualifications" end;
  v_status := coalesce(update_maintenance_plan.changes ->> 'status', v_row."status");
  if v_status not in ('active', 'paused') then
    raise exception 'the status is active or paused' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    raise exception 'a plan needs a title of 1 to 200 characters' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_kind = 'time' and (v_days is null or v_days < 1 or v_meter is not null or v_value is not null) then
    raise exception 'a time plan needs everyDays of at least 1 and no meter' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_kind = 'meter' and (v_meter is null or v_value is null or v_value <= 0 or v_days is not null) then
    raise exception 'a meter plan needs a meterId and an everyValue above 0' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_kind = 'rrule' and (v_rrule is null or v_dtstart is null or v_days is not null or v_meter is not null or v_value is not null) then
    raise exception 'a calendar plan needs an rrule and a dtstart, and no everyDays or meter' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_kind in ('time', 'meter') and (v_rrule is not null or v_dtstart is not null) then
    raise exception 'only a plan of kind rrule takes an rrule and a dtstart' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_kind = 'rrule' and (length(v_rrule) > 500 or v_rrule !~* '(^|[:;])FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)(;|$)') then
    raise exception 'the rrule needs FREQ of DAILY, WEEKLY, MONTHLY or YEARLY and at most 500 characters' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_kind = 'rrule' and not exists (select 1 from pg_catalog.pg_timezone_names n where n.name = v_tz) then
    raise exception 'tz is an IANA time zone name' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_kind is null or v_kind not in ('time', 'meter', 'rrule') then
    raise exception 'the kind is time, meter or rrule' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if exists (
    select 1 from unnest(v_required) k
    where not exists (
      select 1 from "better_supabase"."qualification_types" o
      where o."tenant_id" = v_row."tenant_id" and o."key" = k and o."archived_at" is null
    )
  ) then
    raise exception 'every required qualification is a qualification type key of this organization' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_priority not in ('low', 'normal', 'high', 'urgent') then
    raise exception 'the priority is low, normal, high or urgent' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  begin
    update "better_supabase"."maintenance_plans" x set
      "title" = v_title, "asset_id" = v_asset, "every_days" = v_days, "every_value" = v_value,
      "priority" = v_priority, "status" = v_status,
      "rrule" = v_rrule, "dtstart" = v_dtstart, "tz" = v_tz, "required_qualifications" = v_required,
      "next_due_at" = case v_kind
        when 'time' then coalesce(x."last_done_at", x."created_at") + v_days * interval '1 day'
        when 'rrule' then case
          when update_maintenance_plan.changes ? 'rrule' or update_maintenance_plan.changes ? 'dtstart' or update_maintenance_plan.changes ? 'tz'
            then "better_supabase"."maintenance_next_occurrence"(v_dtstart, v_tz, v_rrule, now())
          else x."next_due_at"
        end
      end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  if update_maintenance_plan.changes ? 'parts' then
    if jsonb_typeof(update_maintenance_plan.changes -> 'parts') is distinct from 'array' then
      raise exception 'parts must be a list' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
    end if;
    delete from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = v_row."id";
    insert into "better_supabase"."maintenance_plan_parts" ("tenant_id", "plan_id", "name", "quantity", "variant_id")
    select v_row."tenant_id", v_row."id", trim(e ->> 'name'), coalesce((e ->> 'quantity')::numeric, 1), nullif(e ->> 'variantId', '')::uuid
    from jsonb_array_elements(update_maintenance_plan.changes -> 'parts') e;
  end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a part needs a name of 1 to 200 characters and a quantity above 0' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end;
  perform "better_supabase".emit_event('maintenance_plan.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'title', v_row."title", 'kind', v_row."kind", 'status', v_row."status"), 'maintenance-plans/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/maintenance');
  perform better_supabase.audit_event(
    event_type => 'maintenance_plan.updated',
    category => 'data',
    target_type => 'maintenance_plan',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'maintenance plan updated',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'title', v_row."title", 'kind', v_row."kind", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'kind', v_row."kind", 'assetId', v_row."asset_id", 'everyDays', v_row."every_days", 'meterId', v_row."meter_id", 'everyValue', v_row."every_value"::text, 'priority', v_row."priority", 'status', v_row."status", 'lastDoneAt', v_row."last_done_at", 'lastDoneValue', v_row."last_done_value"::text, 'nextDueAt', v_row."next_due_at", 'workOrderId', v_row."work_order_id", 'rrule', v_row."rrule", 'dtstart', v_row."dtstart", 'tz', v_row."tz", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'due', v_row."status" = 'active' and v_row."archived_at" is null and v_row."work_order_id" is null and (
      (v_row."kind" in ('time', 'rrule') and v_row."next_due_at" <= now())
      or (v_row."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = v_row."meter_id" and z."reading" >= coalesce(v_row."last_done_value", 0) + v_row."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = v_row."id"
    ), '[]'::jsonb));
end;
$function$;

REVOKE ALL ON FUNCTION "api"."archive_maintenance_plan"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_maintenance_plan"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_maintenance_plan"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_maintenance_plan"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_maintenance_plan"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_maintenance_plan"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_maintenance_plan"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_maintenance_plan"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_maintenance_plan"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_maintenance_plan"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_maintenance_plan"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_maintenance_plan"(uuid) TO "authenticated", "service_role";
