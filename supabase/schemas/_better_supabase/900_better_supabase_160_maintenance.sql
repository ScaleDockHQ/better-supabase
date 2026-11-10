-- better-supabase module: maintenance
-- @bsb-block maintenance@1 managed
-- @bsb-hash sha256:acf96d96be4a1c471db6a75fcc55f7e9c8ca9f3c7835fc9bea42e94d20ba63ff
-- Preventive maintenance plans that fall due by time, by a meter or by an RRULE, meter readings, calibration records, and the dispatch work orders the plans open with their spare parts. Technicians and calibrations can require qualifications.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Preventive maintenance per organization: plans that fall due by time or by a
-- meter, meter readings, calibration records, and the dispatch work orders the
-- plans open.

create table "better_supabase"."maintenance_meters" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null constraint bsb_maintenance_meters_name_check check (length("name") >= 1 and length("name") <= 200),
  "unit" text not null constraint bsb_maintenance_meters_unit_check check (length("unit") >= 1 and length("unit") <= 30),
  "asset_id" uuid,
  -- The latest reading. Readings only go up, so a plan can count from it.
  "reading" numeric not null default 0 constraint bsb_maintenance_meters_reading_check check ("reading" >= 0),
  "read_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "id")
);
create index "maintenance_meters_asset_idx" on "better_supabase"."maintenance_meters" ("tenant_id", "asset_id");
alter table "better_supabase"."maintenance_meters" enable row level security;
revoke all on "better_supabase"."maintenance_meters" from public, anon, authenticated;
grant select on "better_supabase"."maintenance_meters" to authenticated;
grant all on "better_supabase"."maintenance_meters" to service_role;
create policy bsb_maintenance_meters_read on "better_supabase"."maintenance_meters"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('maintenance.read')));

create table "better_supabase"."maintenance_meter_readings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "meter_id" uuid not null,
  "value" numeric not null constraint bsb_maintenance_meter_readings_value_check check ("value" >= 0),
  "read_at" timestamptz not null default now(),
  "read_by" uuid,
  foreign key ("tenant_id", "meter_id") references "better_supabase"."maintenance_meters" ("tenant_id", "id") on delete cascade
);
create index "maintenance_meter_readings_meter_idx" on "better_supabase"."maintenance_meter_readings" ("tenant_id", "meter_id", "read_at" desc);
alter table "better_supabase"."maintenance_meter_readings" enable row level security;
revoke all on "better_supabase"."maintenance_meter_readings" from public, anon, authenticated;
grant select on "better_supabase"."maintenance_meter_readings" to authenticated;
grant all on "better_supabase"."maintenance_meter_readings" to service_role;
create policy bsb_maintenance_meter_readings_read on "better_supabase"."maintenance_meter_readings"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('maintenance.read')));

create table "better_supabase"."maintenance_plans" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "title" text not null constraint bsb_maintenance_plans_title_check check (length("title") >= 1 and length("title") <= 200),
  "asset_id" uuid,
  "kind" text not null constraint bsb_maintenance_plans_kind_check check ("kind" in ('time', 'meter', 'rrule')),
  -- A time plan falls due every_days after it was last done.
  "every_days" integer constraint bsb_maintenance_plans_every_days_check check ("every_days" is null or "every_days" > 0),
  -- A meter plan falls due every_value units of the meter after it was last done.
  "meter_id" uuid,
  "every_value" numeric constraint bsb_maintenance_plans_every_value_check check ("every_value" is null or "every_value" > 0),
  "priority" text not null default 'normal' constraint bsb_maintenance_plans_priority_check check ("priority" in ('low', 'normal', 'high', 'urgent')),
  "status" text not null default 'active' constraint bsb_maintenance_plans_status_check check ("status" in ('active', 'paused')),
  "last_done_at" timestamptz,
  "last_done_value" numeric,
  "next_due_at" timestamptz,
  -- The open work order, so a plan never has two at once.
  "work_order_id" uuid,
  -- An rrule plan (RFC 5545: FREQ DAILY to YEARLY with INTERVAL, COUNT, UNTIL,
  -- BYDAY, BYMONTHDAY, BYMONTH, BYSETPOS and WKST) falls due on each
  -- occurrence from dtstart, read in the time zone tz.
  "rrule" text constraint bsb_maintenance_plans_rrule_check check ("rrule" is null or length("rrule") >= 1 and length("rrule") <= 500),
  "dtstart" timestamptz,
  "tz" text not null default 'UTC',
  -- Qualification type keys the technician of the work order must hold.
  "required_qualifications" text[] not null default '{}',
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "meter_id") references "better_supabase"."maintenance_meters" ("tenant_id", "id"),
  constraint bsb_maintenance_plans_check check (
    ("kind" = 'time' and "every_days" is not null and "meter_id" is null and "every_value" is null and "rrule" is null)
    or ("kind" = 'meter' and "every_days" is null and "meter_id" is not null and "every_value" is not null and "rrule" is null)
    or ("kind" = 'rrule' and "every_days" is null and "meter_id" is null and "every_value" is null and "rrule" is not null and "dtstart" is not null)
  )
);
create index "maintenance_plans_tenant_idx" on "better_supabase"."maintenance_plans" ("tenant_id", "status", "next_due_at");
create index "maintenance_plans_list_idx" on "better_supabase"."maintenance_plans" ("tenant_id", (coalesce("next_due_at", 'infinity'::timestamptz)), "id");
create index "maintenance_plans_asset_idx" on "better_supabase"."maintenance_plans" ("tenant_id", "asset_id");
create index "maintenance_plans_meter_idx" on "better_supabase"."maintenance_plans" ("tenant_id", "meter_id");
create index "maintenance_plans_work_order_idx" on "better_supabase"."maintenance_plans" ("work_order_id") where "work_order_id" is not null;
alter table "better_supabase"."maintenance_plans" enable row level security;
revoke all on "better_supabase"."maintenance_plans" from public, anon, authenticated;
grant select on "better_supabase"."maintenance_plans" to authenticated;
grant all on "better_supabase"."maintenance_plans" to service_role;
create policy bsb_maintenance_plans_read on "better_supabase"."maintenance_plans"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('maintenance.read')));

-- The spare parts a plan's work order carries, copied to it when it opens.
create table "better_supabase"."maintenance_plan_parts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "plan_id" uuid not null,
  "name" text not null constraint bsb_maintenance_plan_parts_name_check check (length("name") >= 1 and length("name") <= 200),
  "quantity" numeric not null default 1 constraint bsb_maintenance_plan_parts_quantity_check check ("quantity" > 0),
  "variant_id" uuid,
  foreign key ("tenant_id", "plan_id") references "better_supabase"."maintenance_plans" ("tenant_id", "id") on delete cascade
);
create index "maintenance_plan_parts_plan_idx" on "better_supabase"."maintenance_plan_parts" ("tenant_id", "plan_id");
alter table "better_supabase"."maintenance_plan_parts" enable row level security;
revoke all on "better_supabase"."maintenance_plan_parts" from public, anon, authenticated;
grant select on "better_supabase"."maintenance_plan_parts" to authenticated;
grant all on "better_supabase"."maintenance_plan_parts" to service_role;
create policy bsb_maintenance_plan_parts_read on "better_supabase"."maintenance_plan_parts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('maintenance.read')));

create table "better_supabase"."maintenance_calibrations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "asset_id" uuid,
  "instrument" text not null constraint bsb_maintenance_calibrations_instrument_check check (length("instrument") >= 1 and length("instrument") <= 200),
  "performed_at" timestamptz not null,
  "due_at" timestamptz,
  "result" text not null constraint bsb_maintenance_calibrations_result_check check ("result" in ('pass', 'fail', 'adjusted')),
  "reference" text constraint bsb_maintenance_calibrations_reference_check check ("reference" is null or length("reference") <= 200),
  "performed_by" uuid,
  -- Qualification type keys the person who calibrated held and the work needs.
  "qualifications" text[] not null default '{}',
  constraint bsb_maintenance_calibrations_check check ("due_at" is null or "due_at" >= "performed_at")
);
create index "maintenance_calibrations_asset_idx" on "better_supabase"."maintenance_calibrations" ("tenant_id", "asset_id", "performed_at" desc);
create index "maintenance_calibrations_list_idx" on "better_supabase"."maintenance_calibrations" ("tenant_id", "performed_at" desc, "id");
create index "maintenance_calibrations_due_idx" on "better_supabase"."maintenance_calibrations" ("tenant_id", "due_at");
alter table "better_supabase"."maintenance_calibrations" enable row level security;
revoke all on "better_supabase"."maintenance_calibrations" from public, anon, authenticated;
grant select on "better_supabase"."maintenance_calibrations" to authenticated;
grant all on "better_supabase"."maintenance_calibrations" to service_role;
create policy bsb_maintenance_calibrations_read on "better_supabase"."maintenance_calibrations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('maintenance.read')));


-- The first occurrence of an RRULE strictly after an instant, or null when
-- the rule has ended (COUNT or UNTIL) or has none within ten years.
create or replace function "better_supabase"."maintenance_next_occurrence"(dtstart timestamptz, tz text, rrule text, after timestamptz)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select min(s) from better_supabase.rrule_occurrences(
    maintenance_next_occurrence.rrule, maintenance_next_occurrence.dtstart, maintenance_next_occurrence.tz,
    tstzrange(maintenance_next_occurrence.after + interval '1 microsecond', maintenance_next_occurrence.after + interval '10 years', '[)')) s;
$$;
revoke execute on function "better_supabase"."maintenance_next_occurrence"(timestamptz, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."maintenance_next_occurrence"(timestamptz, text, text, timestamptz) to authenticated, service_role;

-- Creates a plan. input is { title, kind: 'time' | 'meter' | 'rrule',
-- everyDays, meterId, everyValue, rrule, dtstart, tz, requiredQualifications,
-- assetId, priority, parts: [{ name, quantity, variantId }] }. A time plan
-- falls due everyDays from now; a meter plan everyValue units above the
-- meter's reading; an rrule plan on the next occurrence of its RRULE after
-- now. requiredQualifications are qualification type keys the technician of
-- its work order must hold. Needs maintenance.manage.
create or replace function "better_supabase"."create_maintenance_plan"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."create_maintenance_plan"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_maintenance_plan"(uuid, jsonb) to authenticated, service_role;

-- Changes a plan: title, priority, assetId, everyDays, everyValue, rrule,
-- dtstart, tz, requiredQualifications, status ('active' or 'paused') and parts. The kind and the meter stay. Needs
-- maintenance.manage.
create or replace function "better_supabase"."update_maintenance_plan"(plan_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."update_maintenance_plan"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_maintenance_plan"(uuid, jsonb) to authenticated, service_role;

-- Deletes a plan with its parts. Its open work order stays. Needs
-- maintenance.manage.
create or replace function "better_supabase"."delete_maintenance_plan"(plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."delete_maintenance_plan"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_maintenance_plan"(uuid) to authenticated, service_role;

-- Adds a meter, for example hours run or kilometres, optionally on an asset.
-- Needs maintenance.manage.
create or replace function "better_supabase"."create_maintenance_meter"(tenant uuid, name text, unit text, asset_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."maintenance_meters";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_maintenance_meter.tenant is not null and coalesce(better_supabase.can('tenant', create_maintenance_meter.tenant, 'maintenance.manage'), false))) then
    raise exception 'not allowed to manage maintenance plans' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  begin
    insert into "better_supabase"."maintenance_meters" ("tenant_id", "name", "unit", "asset_id")
    values (create_maintenance_meter.tenant, trim(create_maintenance_meter.name), trim(create_maintenance_meter.unit), create_maintenance_meter.asset_id)
    returning * into v_row;
  exception when check_violation or not_null_violation then
    raise exception 'a meter needs a name of 1 to 200 characters and a unit of 1 to 30' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'unit', v_row."unit", 'assetId', v_row."asset_id", 'reading', v_row."reading"::text, 'readAt', v_row."read_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."create_maintenance_meter"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."create_maintenance_meter"(uuid, text, text, uuid) to authenticated, service_role;

-- Records a reading. A reading never goes below the meter's latest one, and
-- one taken earlier than the latest is kept in the history only. Needs
-- maintenance.record.
create or replace function "better_supabase"."record_meter_reading"(meter_id uuid, value numeric, read_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."maintenance_meters";
  v_at timestamptz := coalesce(record_meter_reading.read_at, now());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_meters" x where x."id" = record_meter_reading.meter_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'maintenance.read'), false))) then
    raise exception 'no such meter' using errcode = 'P0002', hint = 'MAINTENANCE_METER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'maintenance.record'), false))) then
    raise exception 'not allowed to record meter readings' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  if record_meter_reading.value is null or record_meter_reading.value < 0 then
    raise exception 'a reading is a number of 0 or more' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if (v_row."read_at" is null or v_at >= v_row."read_at") and record_meter_reading.value < v_row."reading" then
    raise exception 'a reading is not below the previous one' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  insert into "better_supabase"."maintenance_meter_readings" ("tenant_id", "meter_id", "value", "read_at", "read_by")
  values (v_row."tenant_id", v_row."id", record_meter_reading.value, v_at, auth.uid());
  if v_row."read_at" is null or v_at >= v_row."read_at" then
    update "better_supabase"."maintenance_meters" x set "reading" = record_meter_reading.value, "read_at" = v_at
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  perform "better_supabase".emit_event('maintenance_meter_reading.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'meterId', v_row."id", 'value', record_meter_reading.value::text, 'readAt', v_at), 'maintenance-meters/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/maintenance');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'unit', v_row."unit", 'assetId', v_row."asset_id", 'reading', v_row."reading"::text, 'readAt', v_row."read_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."record_meter_reading"(uuid, numeric, timestamptz) from public, anon;
grant execute on function "better_supabase"."record_meter_reading"(uuid, numeric, timestamptz) to authenticated, service_role;

-- The meters of an organization with their latest reading.
create or replace function "better_supabase"."list_maintenance_meters"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_maintenance_meters.tenant is not null and coalesce(better_supabase.can('tenant', list_maintenance_meters.tenant, 'maintenance.read'), false))) then
    raise exception 'not allowed to read maintenance' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'unit', x."unit", 'assetId', x."asset_id", 'reading', x."reading"::text, 'readAt', x."read_at", 'createdAt', x."created_at") order by x."name", x."id")
    from "better_supabase"."maintenance_meters" x where x."tenant_id" = list_maintenance_meters.tenant
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_maintenance_meters"(uuid) from public, anon;
grant execute on function "better_supabase"."list_maintenance_meters"(uuid) to authenticated, service_role;

-- Records a calibration. input is { assetId, instrument, performedAt, dueAt,
-- result: 'pass' | 'fail' | 'adjusted', reference, qualifications }. The
-- caller must hold every qualification type key in qualifications on the day
-- of performedAt. Needs maintenance.record.
create or replace function "better_supabase"."record_calibration"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."record_calibration"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."record_calibration"(uuid, jsonb) to authenticated, service_role;

-- Calibrations, newest first. filters is { assetId, dueBefore, limit, after, offset, paged,
-- total, totalCap }.
create or replace function "better_supabase"."list_calibrations"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_calibrations.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_asset uuid := (v_filters ->> 'assetId')::uuid;
  v_due timestamptz := (v_filters ->> 'dueBefore')::timestamptz;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_calibrations.tenant is not null and coalesce(better_supabase.can('tenant', list_calibrations.tenant, 'maintenance.read'), false))) then
    raise exception 'not allowed to read maintenance' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'assetId', x."asset_id", 'instrument', x."instrument", 'performedAt', x."performed_at", 'dueAt', x."due_at", 'result', x."result", 'reference', x."reference", 'performedBy', x."performed_by", 'qualifications', to_jsonb(x."qualifications")) as j, jsonb_build_array((x."performed_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_calibrations" x
      where x."tenant_id" = list_calibrations.tenant
        and (v_asset is null or x."asset_id" = v_asset)
        and (v_due is null or x."due_at" <= v_due)
        and (v_after is null or (x."performed_at" <= (v_after ->> 0)::timestamptz and ((x."performed_at" < (v_after ->> 0)::timestamptz) or (x."performed_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."performed_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."maintenance_calibrations" x
      where x."tenant_id" = list_calibrations.tenant
        and (v_asset is null or x."asset_id" = v_asset)
        and (v_due is null or x."due_at" <= v_due)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_calibrations"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_calibrations"(uuid, jsonb) to authenticated, service_role;

-- Plans of an organization, soonest due first. filters is { status, kind,
-- assetId, due: true, limit, after, offset, paged, total, totalCap }. Each plan carries its parts and whether
-- it is due now.
create or replace function "better_supabase"."list_maintenance_plans"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
  v_status text := nullif(v_filters ->> 'status', '');
  v_kind text := nullif(v_filters ->> 'kind', '');
  v_asset uuid := (v_filters ->> 'assetId')::uuid;
  v_due boolean := (v_filters ->> 'due')::boolean;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_maintenance_plans.tenant is not null and coalesce(better_supabase.can('tenant', list_maintenance_plans.tenant, 'maintenance.read'), false))) then
    raise exception 'not allowed to read maintenance' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
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
    ), '[]'::jsonb)) as j, jsonb_build_array((coalesce(x."next_due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_plans" x
      where x."tenant_id" = list_maintenance_plans.tenant
        and (v_status is null or x."status" = v_status)
        and (v_kind is null or x."kind" = v_kind)
        and (v_asset is null or x."asset_id" = v_asset)
        and (v_due is not true or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
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
    ), '[]'::jsonb)) ->> 'due')::boolean)
        and (v_after is null or (coalesce(x."next_due_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."next_due_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."maintenance_plans" x
      where x."tenant_id" = list_maintenance_plans.tenant
        and (v_status is null or x."status" = v_status)
        and (v_kind is null or x."kind" = v_kind)
        and (v_asset is null or x."asset_id" = v_asset)
        and (v_due is not true or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
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
    ), '[]'::jsonb)) ->> 'due')::boolean)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_maintenance_plans"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_maintenance_plans"(uuid, jsonb) to authenticated, service_role;

-- Opens a dispatch work order for every active plan that is due and has none
-- open, with the plan's spare parts on it. It returns [{ planId, workOrderId }].
-- The caller needs maintenance.manage and the dispatch permission to create
-- work orders. Run it on a schedule with the service role.
create or replace function "better_supabase"."generate_maintenance_work_orders"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."generate_maintenance_work_orders"(uuid) from public, anon;
grant execute on function "better_supabase"."generate_maintenance_work_orders"(uuid) to authenticated, service_role;

-- A plan's next due date moves when its work order is done, and a cancelled
-- work order frees the plan to open another one.
create or replace function "better_supabase"."maintenance_work_order_closed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."maintenance_work_order_closed"() from public, anon, authenticated;

-- Assigning a technician to the work order of a plan that requires
-- qualifications fails unless the technician holds them today.
create or replace function "better_supabase"."maintenance_work_order_assigned"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."maintenance_work_order_assigned"() from public, anon, authenticated;
create trigger bsb_maintenance_work_order_technician before update of "technician_id" on "better_supabase"."work_orders"
  for each row when (new."technician_id" is not null and old."technician_id" is distinct from new."technician_id")
  execute function "better_supabase"."maintenance_work_order_assigned"();
create trigger bsb_maintenance_work_order after update of "status" on "better_supabase"."work_orders"
  for each row when (new."status"::text in ('done', 'cancelled') and old."status"::text is distinct from new."status"::text)
  execute function "better_supabase"."maintenance_work_order_closed"();

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."maintenance_plans" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('maintenance.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."maintenance_plans" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."maintenance_plans" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."maintenance_plans" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."maintenance_plan_parts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('maintenance.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."maintenance_plan_parts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."maintenance_plan_parts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."maintenance_plan_parts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."maintenance_meters" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('maintenance.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."maintenance_meters" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."maintenance_meters" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."maintenance_meters" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."maintenance_meter_readings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('maintenance.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."maintenance_meter_readings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."maintenance_meter_readings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."maintenance_meter_readings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."maintenance_calibrations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('maintenance.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."maintenance_calibrations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."maintenance_calibrations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."maintenance_calibrations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.maintenance_plans deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"maintenance_plan","event_prefix":"maintenance_plan"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.maintenance_plan_parts deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"maintenance_plan_part","event_prefix":"maintenance_plan_part"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.maintenance_meters deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"maintenance_meter","event_prefix":"maintenance_meter"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.maintenance_meter_readings deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"maintenance_meter_reading","event_prefix":"maintenance_meter_reading"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.maintenance_calibrations deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"maintenance_calibration","event_prefix":"maintenance_calibration"}');

-- blocks.maintenance.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."maintenance_next_occurrence"(dtstart timestamptz, tz text, rrule text, after timestamptz)
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."maintenance_next_occurrence"($1, $2, $3, $4) $$;
revoke execute on function "api"."maintenance_next_occurrence"(timestamptz, text, text, timestamptz) from public, anon;
grant execute on function "api"."maintenance_next_occurrence"(timestamptz, text, text, timestamptz) to authenticated, service_role;

create or replace function "api"."create_maintenance_plan"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_maintenance_plan"($1, $2) $$;
revoke execute on function "api"."create_maintenance_plan"(uuid, jsonb) from public, anon;
grant execute on function "api"."create_maintenance_plan"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."update_maintenance_plan"(plan_id uuid, changes jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_maintenance_plan"($1, $2) $$;
revoke execute on function "api"."update_maintenance_plan"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_maintenance_plan"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_maintenance_plan"(plan_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_maintenance_plan"($1) $$;
revoke execute on function "api"."delete_maintenance_plan"(uuid) from public, anon;
grant execute on function "api"."delete_maintenance_plan"(uuid) to authenticated, service_role;

create or replace function "api"."create_maintenance_meter"(tenant uuid, name text, unit text, asset_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_maintenance_meter"($1, $2, $3, $4) $$;
revoke execute on function "api"."create_maintenance_meter"(uuid, text, text, uuid) from public, anon;
grant execute on function "api"."create_maintenance_meter"(uuid, text, text, uuid) to authenticated, service_role;

create or replace function "api"."record_meter_reading"(meter_id uuid, value numeric, read_at timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_meter_reading"($1, $2, $3) $$;
revoke execute on function "api"."record_meter_reading"(uuid, numeric, timestamptz) from public, anon;
grant execute on function "api"."record_meter_reading"(uuid, numeric, timestamptz) to authenticated, service_role;

create or replace function "api"."list_maintenance_meters"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_maintenance_meters"($1) $$;
revoke execute on function "api"."list_maintenance_meters"(uuid) from public, anon;
grant execute on function "api"."list_maintenance_meters"(uuid) to authenticated, service_role;

create or replace function "api"."record_calibration"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_calibration"($1, $2) $$;
revoke execute on function "api"."record_calibration"(uuid, jsonb) from public, anon;
grant execute on function "api"."record_calibration"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_calibrations"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_calibrations"($1, $2) $$;
revoke execute on function "api"."list_calibrations"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_calibrations"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_maintenance_plans"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_maintenance_plans"($1, $2) $$;
revoke execute on function "api"."list_maintenance_plans"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_maintenance_plans"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."generate_maintenance_work_orders"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."generate_maintenance_work_orders"($1) $$;
revoke execute on function "api"."generate_maintenance_work_orders"(uuid) from public, anon;
grant execute on function "api"."generate_maintenance_work_orders"(uuid) to authenticated, service_role;
