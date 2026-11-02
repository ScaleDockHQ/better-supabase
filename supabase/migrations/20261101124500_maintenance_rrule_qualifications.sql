SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."maintenance_plans"
  DROP CONSTRAINT "maintenance_plans_check";

ALTER TABLE "better_supabase"."maintenance_plans"
  DROP CONSTRAINT "maintenance_plans_kind_check";

ALTER TABLE "better_supabase"."maintenance_calibrations"
  ADD COLUMN "qualifications" text[] NOT NULL DEFAULT '{}'::text[];

ALTER TABLE "better_supabase"."maintenance_plans"
  ADD COLUMN "rrule" text;

ALTER TABLE "better_supabase"."maintenance_plans"
  ADD COLUMN "dtstart" timestamp WITH time zone;

ALTER TABLE "better_supabase"."maintenance_plans"
  ADD COLUMN "tz" text NOT NULL DEFAULT 'UTC'::text;

ALTER TABLE "better_supabase"."maintenance_plans"
  ADD COLUMN "required_qualifications" text[] NOT NULL DEFAULT '{}'::text[];

CREATE OR REPLACE FUNCTION api.maintenance_next_occurrence (
  dtstart timestamp with time zone,
  tz      text,
  rrule   text,
  after   timestamp with time zone
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."maintenance_next_occurrence"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.maintenance_rule_starts (
  dtstart     timestamp with time zone,
  tz          text,
  rrule       text,
  range_start timestamp with time zone,
  range_end   timestamp with time zone
)
  RETURNS SETOF timestamp WITH time zone
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."maintenance_rule_starts"($1, $2, $3, $4, $5) $function$;

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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'kind', v_row."kind", 'assetId', v_row."asset_id", 'everyDays', v_row."every_days", 'meterId', v_row."meter_id", 'everyValue', v_row."every_value"::text, 'priority', v_row."priority", 'status', v_row."status", 'lastDoneAt', v_row."last_done_at", 'lastDoneValue', v_row."last_done_value"::text, 'nextDueAt', v_row."next_due_at", 'workOrderId', v_row."work_order_id", 'rrule', v_row."rrule", 'dtstart', v_row."dtstart", 'tz', v_row."tz", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'due', v_row."status" = 'active' and v_row."work_order_id" is null and (
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

CREATE OR REPLACE FUNCTION better_supabase.delete_maintenance_plan (
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
  select * into v_row from "better_supabase"."maintenance_plans" x where x."id" = delete_maintenance_plan.plan_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'maintenance.read'), false))) then
    raise exception 'no such maintenance plan' using errcode = 'P0002', hint = 'MAINTENANCE_PLAN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'maintenance.manage'), false))) then
    raise exception 'not allowed to manage maintenance plans' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  delete from "better_supabase"."maintenance_plans" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('maintenance_plan.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'title', v_row."title", 'kind', v_row."kind", 'status', v_row."status"), 'maintenance-plans/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/maintenance');
  perform better_supabase.audit_event(
    event_type => 'maintenance_plan.deleted',
    category => 'data',
    target_type => 'maintenance_plan',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'maintenance plan deleted',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'title', v_row."title", 'kind', v_row."kind", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'kind', v_row."kind", 'assetId', v_row."asset_id", 'everyDays', v_row."every_days", 'meterId', v_row."meter_id", 'everyValue', v_row."every_value"::text, 'priority', v_row."priority", 'status', v_row."status", 'lastDoneAt', v_row."last_done_at", 'lastDoneValue', v_row."last_done_value"::text, 'nextDueAt', v_row."next_due_at", 'workOrderId', v_row."work_order_id", 'rrule', v_row."rrule", 'dtstart', v_row."dtstart", 'tz', v_row."tz", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
    where x."tenant_id" = generate_maintenance_work_orders.tenant and x."status" = 'active' and x."work_order_id" is null
    order by x."next_due_at" nulls last, x."id"
    for update
  loop
    v_view := jsonb_build_object('id', v_plan."id", 'organizationId', v_plan."tenant_id", 'title', v_plan."title", 'kind', v_plan."kind", 'assetId', v_plan."asset_id", 'everyDays', v_plan."every_days", 'meterId', v_plan."meter_id", 'everyValue', v_plan."every_value"::text, 'priority', v_plan."priority", 'status', v_plan."status", 'lastDoneAt', v_plan."last_done_at", 'lastDoneValue', v_plan."last_done_value"::text, 'nextDueAt', v_plan."next_due_at", 'workOrderId', v_plan."work_order_id", 'rrule', v_plan."rrule", 'dtstart', v_plan."dtstart", 'tz', v_plan."tz", 'requiredQualifications', to_jsonb(v_plan."required_qualifications"), 'createdAt', v_plan."created_at", 'updatedAt', v_plan."updated_at") || jsonb_build_object(
    'due', v_plan."status" = 'active' and v_plan."work_order_id" is null and (
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

CREATE OR REPLACE FUNCTION better_supabase.list_calibrations (
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
  v_filters jsonb := coalesce(list_calibrations.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_calibrations.tenant is not null and coalesce(better_supabase.can('tenant', list_calibrations.tenant, 'maintenance.read'), false))) then
    raise exception 'not allowed to read maintenance' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'assetId', y."asset_id", 'instrument', y."instrument", 'performedAt', y."performed_at", 'dueAt', y."due_at", 'result', y."result", 'reference', y."reference", 'performedBy', y."performed_by", 'qualifications', to_jsonb(y."qualifications")) order by y."performed_at" desc, y."id")
    from (
      select * from "better_supabase"."maintenance_calibrations" x
      where x."tenant_id" = list_calibrations.tenant
        and (not v_filters ? 'assetId' or x."asset_id" = (v_filters ->> 'assetId')::uuid)
        and (not v_filters ? 'dueBefore' or x."due_at" <= (v_filters ->> 'dueBefore')::timestamptz)
      order by x."performed_at" desc, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
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
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_maintenance_plans.tenant is not null and coalesce(better_supabase.can('tenant', list_maintenance_plans.tenant, 'maintenance.read'), false))) then
    raise exception 'not allowed to read maintenance' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(y.view order by y.due_first, y.id)
    from (
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
    'due', x."status" = 'active' and x."work_order_id" is null and (
      (x."kind" in ('time', 'rrule') and x."next_due_at" <= now())
      or (x."kind" = 'meter' and exists (
        select 1 from "better_supabase"."maintenance_meters" z
        where z."id" = x."meter_id" and z."reading" >= coalesce(x."last_done_value", 0) + x."every_value"
      ))
    ),
    'parts', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name", 'quantity', y."quantity"::text, 'variantId', y."variant_id") order by y."name", y."id")
      from "better_supabase"."maintenance_plan_parts" y where y."plan_id" = x."id"
    ), '[]'::jsonb)) as view, x."id" as id, x."next_due_at" as due_first
      from "better_supabase"."maintenance_plans" x
      where x."tenant_id" = list_maintenance_plans.tenant
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'kind' or x."kind" = v_filters ->> 'kind')
        and (not v_filters ? 'assetId' or x."asset_id" = (v_filters ->> 'assetId')::uuid)
      order by x."next_due_at" nulls last, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
    where (v_filters ->> 'due') is distinct from 'true' or (y.view ->> 'due')::boolean
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.maintenance_next_occurrence (
  dtstart timestamp with time zone,
  tz      text,
  rrule   text,
  after   timestamp with time zone
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select min(s) from "better_supabase"."maintenance_rule_starts"(
    maintenance_next_occurrence.dtstart, maintenance_next_occurrence.tz, maintenance_next_occurrence.rrule,
    maintenance_next_occurrence.after + interval '1 microsecond', maintenance_next_occurrence.after + interval '10 years') s;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.maintenance_rule_starts (
  dtstart     timestamp with time zone,
  tz          text,
  rrule       text,
  range_start timestamp with time zone,
  range_end   timestamp with time zone
)
  RETURNS SETOF timestamp WITH time zone
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_parts jsonb;
  v_freq text;
  v_interval integer := 1;
  v_count integer;
  v_until timestamptz;
  v_alldays integer[] := '{}';
  v_ordinals integer[] := '{}';
  v_ordinal_days integer[] := '{}';
  v_bymonthday integer[] := '{}';
  v_bymonth integer[] := '{}';
  v_bysetpos integer[] := '{}';
  v_wkst integer := 1;
  v_local timestamp;
  v_anchor date;
  v_time time;
  v_week date;
  v_moved date;
  v_target date;
  v_periods integer;
  v_first integer := 0;
  v_generated integer := 0;
  v_found integer := 0;
  v_index integer;
  v_dates date[];
  v_sorted date[];
  v_date date;
  v_when timestamptz;
  v_year integer;
  v_month integer;
  v_len integer;
  v_day integer;
  v_item text;
  v_match text[];
  v_i integer;
  v_names constant text[] := array['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
begin
  if maintenance_rule_starts.dtstart is null or maintenance_rule_starts.range_start is null or maintenance_rule_starts.range_end is null then
    return;
  end if;
  v_local := maintenance_rule_starts.dtstart at time zone coalesce(maintenance_rule_starts.tz, 'UTC');
  v_anchor := v_local::date;
  v_time := v_local::time;
  select coalesce(jsonb_object_agg(upper(btrim(split_part(p, '=', 1))), btrim(split_part(p, '=', 2))), '{}'::jsonb)
    into v_parts
  from unnest(string_to_array(regexp_replace(btrim(coalesce(maintenance_rule_starts.rrule, '')), '^RRULE:', '', 'i'), ';')) p
  where p like '%=%';
  v_freq := upper(v_parts ->> 'FREQ');
  if v_freq is null or v_freq not in ('DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY') then
    if maintenance_rule_starts.dtstart >= maintenance_rule_starts.range_start and maintenance_rule_starts.dtstart < maintenance_rule_starts.range_end then
      return next maintenance_rule_starts.dtstart;
    end if;
    return;
  end if;
  if v_parts ->> 'INTERVAL' ~ '^[0-9]{1,6}$' then
    v_interval := greatest((v_parts ->> 'INTERVAL')::integer, 1);
  end if;
  if v_parts ->> 'COUNT' ~ '^[0-9]{1,6}$' then
    v_count := (v_parts ->> 'COUNT')::integer;
  end if;
  if v_parts ->> 'UNTIL' ~ '^[0-9]{8}T[0-9]{6}Z$' then
    v_until := (regexp_replace(v_parts ->> 'UNTIL', '^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z$', '\1-\2-\3 \4:\5:\6+00'))::timestamptz;
  elsif v_parts ->> 'UNTIL' ~ '^[0-9]{8}$' then
    v_until := ((to_date(v_parts ->> 'UNTIL', 'YYYYMMDD') + 1)::timestamp at time zone coalesce(maintenance_rule_starts.tz, 'UTC')) - interval '1 microsecond';
  end if;
  if upper(v_parts ->> 'WKST') = any (v_names) then
    v_wkst := array_position(v_names, upper(v_parts ->> 'WKST'));
  end if;
  foreach v_item in array string_to_array(coalesce(upper(v_parts ->> 'BYDAY'), ''), ',') loop
    v_match := regexp_match(btrim(v_item), '^([+-]?[0-9]{1,2})?(MO|TU|WE|TH|FR|SA|SU)$');
    continue when v_match is null;
    v_alldays := v_alldays || array_position(v_names, v_match[2]);
    if v_match[1] is not null and v_match[1]::integer <> 0 then
      v_ordinals := v_ordinals || v_match[1]::integer;
      v_ordinal_days := v_ordinal_days || array_position(v_names, v_match[2]);
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYMONTHDAY', ''), ',') loop
    if btrim(v_item) ~ '^[+-]?[0-9]{1,2}$' and btrim(v_item)::integer <> 0 then
      v_bymonthday := v_bymonthday || btrim(v_item)::integer;
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYMONTH', ''), ',') loop
    if btrim(v_item) ~ '^[0-9]{1,2}$' and btrim(v_item)::integer between 1 and 12 then
      v_bymonth := v_bymonth || btrim(v_item)::integer;
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYSETPOS', ''), ',') loop
    if btrim(v_item) ~ '^[+-]?[0-9]{1,3}$' and btrim(v_item)::integer <> 0 then
      v_bysetpos := v_bysetpos || btrim(v_item)::integer;
    end if;
  end loop;
  -- Without COUNT, start a period before the window instead of at dtstart.
  if v_count is null then
    v_target := (maintenance_rule_starts.range_start at time zone coalesce(maintenance_rule_starts.tz, 'UTC'))::date;
    if v_target > v_anchor then
      v_periods := case v_freq
        when 'DAILY' then v_target - v_anchor
        when 'WEEKLY' then floor((v_target - (v_anchor - ((extract(isodow from v_anchor)::integer - v_wkst + 7) % 7)))::numeric / 7)::integer
        when 'MONTHLY' then (extract(year from v_target)::integer - extract(year from v_anchor)::integer) * 12 + extract(month from v_target)::integer - extract(month from v_anchor)::integer
        else extract(year from v_target)::integer - extract(year from v_anchor)::integer
      end;
      v_first := greatest(0, floor(v_periods::numeric / v_interval)::integer - 1);
    end if;
  end if;
  for v_index in v_first .. v_first + 3999 loop
    v_dates := '{}';
    if v_freq = 'DAILY' then
      v_date := v_anchor + v_index * v_interval;
      if cardinality(v_alldays) = 0 or extract(isodow from v_date)::integer = any (v_alldays) then
        v_dates := array[v_date];
      end if;
    elsif v_freq = 'WEEKLY' then
      v_week := v_anchor - ((extract(isodow from v_anchor)::integer - v_wkst + 7) % 7) + v_index * v_interval * 7;
      select coalesce(array_agg(v_week + ((d - v_wkst + 7) % 7)), '{}') into v_dates
      from unnest(case when cardinality(v_alldays) = 0 then array[extract(isodow from v_anchor)::integer] else v_alldays end) d;
    else
      if v_freq = 'MONTHLY' then
        v_moved := (v_anchor + make_interval(months => v_index * v_interval))::date;
      else
        v_moved := (v_anchor + make_interval(years => v_index * v_interval))::date;
      end if;
      v_year := extract(year from v_moved)::integer;
      foreach v_month in array case when cardinality(v_bymonth) = 0 then array[extract(month from v_moved)::integer] else v_bymonth end loop
        v_len := extract(day from (make_date(v_year, v_month, 1) + interval '1 month' - interval '1 day'))::integer;
        if cardinality(v_ordinals) > 0 then
          for v_i in 1 .. cardinality(v_ordinals) loop
            if v_ordinals[v_i] > 0 then
              v_day := 1 + ((v_ordinal_days[v_i] - extract(isodow from make_date(v_year, v_month, 1))::integer + 7) % 7) + (v_ordinals[v_i] - 1) * 7;
            else
              v_day := v_len - ((extract(isodow from make_date(v_year, v_month, v_len))::integer - v_ordinal_days[v_i] + 7) % 7) + (v_ordinals[v_i] + 1) * 7;
            end if;
            if v_day between 1 and v_len then
              v_dates := v_dates || make_date(v_year, v_month, v_day);
            end if;
          end loop;
        elsif cardinality(v_alldays) > 0 then
          v_dates := v_dates || array(
            select make_date(v_year, v_month, d) from generate_series(1, v_len) d
            where extract(isodow from make_date(v_year, v_month, d))::integer = any (v_alldays)
          );
        elsif cardinality(v_bymonthday) > 0 then
          foreach v_day in array v_bymonthday loop
            v_day := case when v_day > 0 then v_day else v_len + v_day + 1 end;
            if v_day between 1 and v_len then
              v_dates := v_dates || make_date(v_year, v_month, v_day);
            end if;
          end loop;
        elsif extract(day from v_moved)::integer <= v_len then
          v_dates := v_dates || make_date(v_year, v_month, extract(day from v_moved)::integer);
        end if;
      end loop;
    end if;
    if cardinality(v_bysetpos) > 0 and cardinality(v_dates) > 0 then
      select array_agg(d order by d) into v_sorted from (select distinct d from unnest(v_dates) d) s;
      select coalesce(array_agg(distinct v_sorted[case when p > 0 then p else cardinality(v_sorted) + p + 1 end]), '{}') into v_dates
      from unnest(v_bysetpos) p
      where (case when p > 0 then p else cardinality(v_sorted) + p + 1 end) between 1 and cardinality(v_sorted);
    end if;
    foreach v_date in array coalesce((select array_agg(d order by d) from unnest(v_dates) d), '{}') loop
      v_when := (v_date + v_time) at time zone coalesce(maintenance_rule_starts.tz, 'UTC');
      -- A wall time that happens twice (DST ends) takes the earlier instant,
      -- as Temporal's compatible disambiguation does; Postgres takes the later.
      if ((v_when - interval '1 hour') at time zone coalesce(maintenance_rule_starts.tz, 'UTC')) = v_date + v_time then
        v_when := v_when - interval '1 hour';
      elsif ((v_when - interval '30 minutes') at time zone coalesce(maintenance_rule_starts.tz, 'UTC')) = v_date + v_time then
        v_when := v_when - interval '30 minutes';
      end if;
      continue when v_when < maintenance_rule_starts.dtstart;
      if v_until is not null and v_when > v_until then
        return;
      end if;
      v_generated := v_generated + 1;
      if v_count is not null and v_generated > v_count then
        return;
      end if;
      if v_when >= maintenance_rule_starts.range_end then
        return;
      end if;
      continue when v_when < maintenance_rule_starts.range_start;
      return next v_when;
      v_found := v_found + 1;
      if v_found >= 1000 then
        return;
      end if;
    end loop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.maintenance_work_order_assigned()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_plan "better_supabase"."maintenance_plans";
  v_key text;
begin
  for v_plan in
    select * from "better_supabase"."maintenance_plans" x
    where x."work_order_id" = new."id" and cardinality(x."required_qualifications") > 0
  loop
    foreach v_key in array v_plan."required_qualifications" loop
    if not coalesce("better_supabase"."qualified_holders"(new."tenant_id", v_key, 'member', current_date) ? (new."technician_id")::text, false) then
      raise exception 'the person doesn''t hold a qualification the work requires' using errcode = '42501', hint = 'MAINTENANCE_UNQUALIFIED';
    end if;
  end loop;
  end loop;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.maintenance_work_order_closed()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_plan "better_supabase"."maintenance_plans";
  v_done timestamptz;
  v_reading numeric;
begin
  select * into v_plan from "better_supabase"."maintenance_plans" x where x."work_order_id" = new."id" for update;
  if not found then
    return new;
  end if;
  if new."status"::text = 'cancelled' then
    update "better_supabase"."maintenance_plans" x set "work_order_id" = null, "updated_at" = now() where x."id" = v_plan."id";
    return new;
  end if;
  v_done := coalesce(new."completed_at", now());
  select z."reading" into v_reading from "better_supabase"."maintenance_meters" z where z."id" = v_plan."meter_id";
  update "better_supabase"."maintenance_plans" x set
    "work_order_id" = null,
    "last_done_at" = v_done,
    "last_done_value" = v_reading,
    "next_due_at" = case x."kind"
      when 'time' then v_done + x."every_days" * interval '1 day'
      -- Done early counts for the occurrence it was due on; done late skips the missed ones.
      when 'rrule' then "better_supabase"."maintenance_next_occurrence"(x."dtstart", x."tz", x."rrule", greatest(v_done, coalesce(x."next_due_at", v_done)))
    end,
    "updated_at" = now()
  where x."id" = v_plan."id"
  returning * into v_plan;
  perform "better_supabase".emit_event('maintenance_plan.completed', jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'title', v_plan."title", 'kind', v_plan."kind", 'status', v_plan."status", 'workOrderId', new."id"), 'maintenance-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/maintenance');
  perform better_supabase.audit_event(
    event_type => 'maintenance_plan.completed',
    category => 'data',
    target_type => 'maintenance_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."title",
    summary => 'maintenance work order done',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'title', v_plan."title", 'kind', v_plan."kind", 'status', v_plan."status", 'workOrderId', new."id")
  );
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_calibration (
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
  v_row "better_supabase"."maintenance_calibrations";
  v_key text;
  v_quals text[] := '{}';
  v_at timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (record_calibration.tenant is not null and coalesce(better_supabase.can('tenant', record_calibration.tenant, 'maintenance.record'), false))) then
    raise exception 'not allowed to record calibrations' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  if jsonb_typeof(record_calibration.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if record_calibration.input ? 'qualifications' then
    if jsonb_typeof(record_calibration.input -> 'qualifications') is distinct from 'array' then
      raise exception 'qualifications is a list of qualification type keys' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
    end if;
    select coalesce(array_agg(distinct k), '{}') into v_quals from jsonb_array_elements_text(record_calibration.input -> 'qualifications') k;
  end if;
  begin
    v_at := (record_calibration.input ->> 'performedAt')::timestamptz;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'performedAt is a timestamp' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end;
  if exists (
    select 1 from unnest(v_quals) k
    where not exists (
      select 1 from "better_supabase"."qualification_types" o
      where o."tenant_id" = record_calibration.tenant and o."key" = k and o."archived_at" is null
    )
  ) then
    raise exception 'every required qualification is a qualification type key of this organization' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if cardinality(v_quals) > 0 and auth.uid() is null then
    raise exception 'a calibration with qualifications needs a signed-in person who performed it' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  foreach v_key in array v_quals loop
    if not coalesce("better_supabase"."qualified_holders"(record_calibration.tenant, v_key, 'member', v_at::date) ? (auth.uid())::text, false) then
      raise exception 'the person doesn''t hold a qualification the work requires' using errcode = '42501', hint = 'MAINTENANCE_UNQUALIFIED';
    end if;
  end loop;
  begin
    insert into "better_supabase"."maintenance_calibrations" ("tenant_id", "asset_id", "instrument", "performed_at", "due_at", "result", "reference", "performed_by", "qualifications")
    values (record_calibration.tenant, nullif(record_calibration.input ->> 'assetId', '')::uuid, trim(record_calibration.input ->> 'instrument'),
      v_at, (record_calibration.input ->> 'dueAt')::timestamptz,
      record_calibration.input ->> 'result', nullif(trim(record_calibration.input ->> 'reference'), ''), auth.uid(), v_quals)
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'a calibration needs an instrument, a performedAt, a dueAt on or after it, and a result of pass, fail, adjusted' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end;
  perform "better_supabase".emit_event('maintenance_calibration.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'assetId', v_row."asset_id", 'instrument', v_row."instrument", 'result', v_row."result"), 'maintenance-calibrations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/maintenance');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'assetId', v_row."asset_id", 'instrument', v_row."instrument", 'performedAt', v_row."performed_at", 'dueAt', v_row."due_at", 'result', v_row."result", 'reference', v_row."reference", 'performedBy', v_row."performed_by", 'qualifications', to_jsonb(v_row."qualifications"));
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'kind', v_row."kind", 'assetId', v_row."asset_id", 'everyDays', v_row."every_days", 'meterId', v_row."meter_id", 'everyValue', v_row."every_value"::text, 'priority', v_row."priority", 'status', v_row."status", 'lastDoneAt', v_row."last_done_at", 'lastDoneValue', v_row."last_done_value"::text, 'nextDueAt', v_row."next_due_at", 'workOrderId', v_row."work_order_id", 'rrule', v_row."rrule", 'dtstart', v_row."dtstart", 'tz', v_row."tz", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'due', v_row."status" = 'active' and v_row."work_order_id" is null and (
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

ALTER TABLE "better_supabase"."maintenance_plans"
  ADD CONSTRAINT "maintenance_plans_check" CHECK ((((kind = 'time'::text) AND (every_days IS
    NOT NULL) AND (meter_id IS NULL) AND (every_value IS NULL) AND (rrule IS NULL)) OR ((kind = 'meter'::text) AND (every_days IS NULL) AND (meter_id IS
    NOT NULL) AND (every_value IS NOT NULL) AND (rrule IS NULL)) OR ((kind = 'rrule'::text) AND (every_days IS NULL) AND (meter_id IS NULL) AND (every_value IS NULL) AND (rrule IS
    NOT NULL) AND (dtstart IS NOT NULL))));

ALTER TABLE "better_supabase"."maintenance_plans"
  ADD CONSTRAINT "maintenance_plans_kind_check" CHECK ((kind = ANY (ARRAY['time'::text, 'meter'::text, 'rrule'::text])));

ALTER TABLE "better_supabase"."maintenance_plans"
  ADD CONSTRAINT "maintenance_plans_rrule_check" CHECK (((rrule IS NULL) OR ((length(rrule) >= 1) AND (length(rrule) <= 500))));

CREATE TRIGGER bsb_maintenance_work_order_technician
  BEFORE UPDATE OF technician_id ON better_supabase.work_orders
  FOR EACH ROW
  WHEN (((new.technician_id IS NOT NULL) AND (old.technician_id IS DISTINCT FROM new.technician_id)))
  EXECUTE FUNCTION better_supabase.maintenance_work_order_assigned();

REVOKE ALL ON FUNCTION "api"."maintenance_next_occurrence"(timestamp WITH time zone, text, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."maintenance_next_occurrence"(timestamp WITH time zone, text, text, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."maintenance_rule_starts"(timestamp WITH time zone, text, text, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "api"."maintenance_rule_starts"(timestamp WITH time zone, text, text, timestamp WITH time zone, timestamp WITH time zone)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."maintenance_next_occurrence"(timestamp WITH time zone, text, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."maintenance_next_occurrence"(timestamp WITH time zone, text, text, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."maintenance_rule_starts"(timestamp WITH time zone, text, text, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."maintenance_rule_starts"(timestamp WITH time zone, text, text, timestamp WITH time zone, timestamp WITH time zone)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."maintenance_work_order_assigned"() FROM PUBLIC;
