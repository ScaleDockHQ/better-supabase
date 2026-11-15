SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.get_count_plan (
  plan_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_count_plan"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_lims_method (
  method_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_lims_method"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_maintenance_meter (
  meter_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_maintenance_meter"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_pick_wave (
  wave_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_pick_wave"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_putaway_rule (
  rule_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_putaway_rule"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_till (
  till_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_till"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_work_center (
  work_center_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_work_center"($1) $function$;

CREATE OR REPLACE FUNCTION api.page_boms (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_boms"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_count_plans (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_count_plans"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_lims_methods (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_lims_methods"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_maintenance_meters (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_maintenance_meters"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_pick_waves (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_pick_waves"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_work_centers (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_work_centers"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_count_plan (
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
  v_tenant uuid;
  v_row jsonb;
begin
  select x."tenant_id", jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'locationId', x."location_id", 'everyDays', x."every_days", 'variantIds', to_jsonb(coalesce(x."variant_ids", '{}'::uuid[])), 'varianceLimitPct', x."variance_limit_pct"::text, 'nextRunOn', x."next_run_on", 'lastRunAt', x."last_run_at", 'lastCountId', x."last_count_id", 'active', x."active", 'createdAt', x."created_at")
    into v_tenant, v_row
    from "better_supabase"."count_plans" x
    where x."id" = get_count_plan.plan_id;
  if v_row is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'warehouse.read'), false))) then
    raise exception 'not allowed to read count plans' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_lims_method (
  method_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row jsonb;
begin
  select x."tenant_id", jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'unit', x."unit", 'lowerLimit', x."lower_limit", 'upperLimit', x."upper_limit", 'formId', x."form_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at")
    into v_tenant, v_row
    from "better_supabase"."lims_methods" x
    where x."id" = get_lims_method.method_id;
  if v_row is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'lims.read'), false))) then
    raise exception 'not allowed to read test methods' using errcode = '42501', hint = 'LIMS_FORBIDDEN';
  end if;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_maintenance_meter (
  meter_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row jsonb;
begin
  select x."tenant_id", jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'unit', x."unit", 'assetId', x."asset_id", 'reading', x."reading"::text, 'readAt', x."read_at", 'createdAt', x."created_at")
    into v_tenant, v_row
    from "better_supabase"."maintenance_meters" x
    where x."id" = get_maintenance_meter.meter_id;
  if v_row is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'maintenance.read'), false))) then
    raise exception 'not allowed to read maintenance' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_pick_wave (
  wave_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row jsonb;
begin
  select x."tenant_id", jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'locationId', x."location_id", 'status', x."status", 'releasedAt', x."released_at", 'completedAt', x."completed_at", 'createdAt', x."created_at")
      || jsonb_build_object(
        'lists', (select count(*) from "better_supabase"."pick_lists" z where z."wave_id" = x."id" and z."status" <> 'cancelled'),
        'openLists', (select count(*) from "better_supabase"."pick_lists" z where z."wave_id" = x."id" and z."status" = 'open'))
    into v_tenant, v_row
    from "better_supabase"."pick_waves" x
    where x."id" = get_pick_wave.wave_id;
  if v_row is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'warehouse.read'), false))) then
    raise exception 'not allowed to read pick waves' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_putaway_rule (
  rule_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row jsonb;
begin
  select x."tenant_id", jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id",
    'binId', x."bin_id", 'variantId', x."variant_id", 'priority', x."priority",
    'maxQuantity', x."max_quantity"::text, 'active', x."active", 'createdAt', x."created_at")
    into v_tenant, v_row
    from "better_supabase"."putaway_rules" x
    where x."id" = get_putaway_rule.rule_id;
  if v_row is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'warehouse.read'), false))) then
    raise exception 'not allowed to read putaway rules' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_till (
  till_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row jsonb;
begin
  select x."tenant_id", jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'currency', x."currency", 'accountId', x."account_id", 'location', x."location", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at")
    into v_tenant, v_row
    from "better_supabase"."tills" x
    where x."id" = get_till.till_id;
  if v_row is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'tills.read'), false))) then
    raise exception 'not allowed to read tills' using errcode = '42501', hint = 'TILL_FORBIDDEN';
  end if;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_work_center (
  work_center_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row jsonb;
begin
  select x."tenant_id", jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'assetId', x."asset_id", 'hoursPerDay', x."hours_per_day"::text, 'costRate', x."cost_rate"::text, 'currency', x."currency", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at")
    into v_tenant, v_row
    from "better_supabase"."work_centers" x
    where x."id" = get_work_center.work_center_id;
  if v_row is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'manufacturing.read'), false))) then
    raise exception 'not allowed to read work centers' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  return v_row;
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
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_calibrations.tenant is not null and coalesce(better_supabase.can('tenant', list_calibrations.tenant, 'maintenance.read'), false))) then
    raise exception 'not allowed to read maintenance' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('result') then
      raise exception 'facet is one of result' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'result' then (x."result")::text end) as v
      from "better_supabase"."maintenance_calibrations" x
      where x."tenant_id" = list_calibrations.tenant
        and (v_search is null or coalesce(x."reference", '') ilike v_search or coalesce(x."instrument", '') ilike v_search)
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), '') is null or x."due_at" <= (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), ''))::timestamptz)
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
      select 1 from "better_supabase"."maintenance_calibrations" x
      where x."tenant_id" = list_calibrations.tenant
        and (v_search is null or coalesce(x."reference", '') ilike v_search or coalesce(x."instrument", '') ilike v_search)
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), '') is null or x."due_at" <= (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), ''))::timestamptz)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('performedAt', 'dueAt') then
    raise exception 'sort is one of performedAt, dueAt' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
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
        and (v_search is null or coalesce(x."reference", '') ilike v_search or coalesce(x."instrument", '') ilike v_search)
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), '') is null or x."due_at" <= (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), ''))::timestamptz)
        and (v_after is null or (x."performed_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."performed_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
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
        and (v_search is null or coalesce(x."reference", '') ilike v_search or coalesce(x."instrument", '') ilike v_search)
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), '') is null or x."due_at" <= (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), ''))::timestamptz)
        and (v_after is null or (x."performed_at" <= (v_after ->> 0)::timestamptz and ((x."performed_at" < (v_after ->> 0)::timestamptz) or (x."performed_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."performed_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'performedAt' and coalesce(v_dir, 'desc') = 'asc' then
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
        and (v_search is null or coalesce(x."reference", '') ilike v_search or coalesce(x."instrument", '') ilike v_search)
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), '') is null or x."due_at" <= (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), ''))::timestamptz)
        and (v_after is null or (x."performed_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."performed_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'performedAt' and coalesce(v_dir, 'desc') = 'desc' then
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
        and (v_search is null or coalesce(x."reference", '') ilike v_search or coalesce(x."instrument", '') ilike v_search)
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), '') is null or x."due_at" <= (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), ''))::timestamptz)
        and (v_after is null or (x."performed_at" <= (v_after ->> 0)::timestamptz and ((x."performed_at" < (v_after ->> 0)::timestamptz) or (x."performed_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."performed_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'assetId', x."asset_id", 'instrument', x."instrument", 'performedAt', x."performed_at", 'dueAt', x."due_at", 'result', x."result", 'reference', x."reference", 'performedBy', x."performed_by", 'qualifications', to_jsonb(x."qualifications")) as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_calibrations" x
      where x."tenant_id" = list_calibrations.tenant
        and (v_search is null or coalesce(x."reference", '') ilike v_search or coalesce(x."instrument", '') ilike v_search)
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), '') is null or x."due_at" <= (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), ''))::timestamptz)
        and (v_after is null or (coalesce(x."due_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."due_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'assetId', x."asset_id", 'instrument', x."instrument", 'performedAt', x."performed_at", 'dueAt', x."due_at", 'result', x."result", 'reference', x."reference", 'performedBy', x."performed_by", 'qualifications', to_jsonb(x."qualifications")) as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_calibrations" x
      where x."tenant_id" = list_calibrations.tenant
        and (v_search is null or coalesce(x."reference", '') ilike v_search or coalesce(x."instrument", '') ilike v_search)
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), '') is null or x."due_at" <= (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), ''))::timestamptz)
        and (v_after is null or (coalesce(x."due_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."due_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."due_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."due_at", 'infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."maintenance_calibrations" x
      where x."tenant_id" = list_calibrations.tenant
        and (v_search is null or coalesce(x."reference", '') ilike v_search or coalesce(x."instrument", '') ilike v_search)
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), '') is null or x."due_at" <= (nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), ''))::timestamptz)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
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
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
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
        and (v_search is null or x."title" ilike v_search)
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
        and (v_search is null or x."title" ilike v_search)
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
        and (v_search is null or x."title" ilike v_search)
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
        and (v_search is null or x."title" ilike v_search)
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
        and (v_search is null or x."title" ilike v_search)
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
        and (v_search is null or x."title" ilike v_search)
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
        and (v_search is null or x."title" ilike v_search)
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
        and (v_search is null or x."title" ilike v_search)
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
        and (v_search is null or x."title" ilike v_search)
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

CREATE OR REPLACE FUNCTION better_supabase.list_production_orders (
  tenant  uuid,
  filters jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_production_orders.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_production_orders.tenant is not null and coalesce(better_supabase.can('tenant', list_production_orders.tenant, 'manufacturing.read'), false))) then
    raise exception 'not allowed to read production orders' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_search is null or x."number" ilike v_search or coalesce(x."note", '') ilike v_search)
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
      select 1 from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_search is null or x."number" ilike v_search or coalesce(x."note", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('dueOn', 'createdAt', 'number') then
    raise exception 'sort is one of dueOn, createdAt, number' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'variantId', x."variant_id", 'bomId', x."bom_id", 'quantity', x."quantity"::text, 'locationId', x."location_id", 'dueOn', x."due_on", 'status', x."status", 'producedQuantity', x."produced_quantity"::text, 'scrapQuantity', x."scrap_quantity"::text, 'outputLotId', x."output_lot_id", 'materialCost', x."material_cost"::text, 'laborCost', x."labor_cost"::text, 'currency', x."currency", 'note', x."note", 'releasedAt', x."released_at", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."due_on", 'infinity'::date))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_search is null or x."number" ilike v_search or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (coalesce(x."due_on", 'infinity'::date) >= (v_after ->> 0)::date and ((coalesce(x."due_on", 'infinity'::date) > (v_after ->> 0)::date) or (coalesce(x."due_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" < (v_after ->> 1)::bigint) or (coalesce(x."due_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."due_on", 'infinity'::date) asc, x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'variantId', x."variant_id", 'bomId', x."bom_id", 'quantity', x."quantity"::text, 'locationId', x."location_id", 'dueOn', x."due_on", 'status', x."status", 'producedQuantity', x."produced_quantity"::text, 'scrapQuantity', x."scrap_quantity"::text, 'outputLotId', x."output_lot_id", 'materialCost', x."material_cost"::text, 'laborCost', x."labor_cost"::text, 'currency', x."currency", 'note', x."note", 'releasedAt', x."released_at", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."due_on", 'infinity'::date))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_search is null or x."number" ilike v_search or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (coalesce(x."due_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."due_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."due_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" < (v_after ->> 1)::bigint) or (coalesce(x."due_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."due_on", 'infinity'::date) desc, x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'variantId', x."variant_id", 'bomId', x."bom_id", 'quantity', x."quantity"::text, 'locationId', x."location_id", 'dueOn', x."due_on", 'status', x."status", 'producedQuantity', x."produced_quantity"::text, 'scrapQuantity', x."scrap_quantity"::text, 'outputLotId', x."output_lot_id", 'materialCost', x."material_cost"::text, 'laborCost', x."labor_cost"::text, 'currency', x."currency", 'note', x."note", 'releasedAt', x."released_at", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."due_on", 'infinity'::date))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_search is null or x."number" ilike v_search or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (coalesce(x."due_on", 'infinity'::date) >= (v_after ->> 0)::date and ((coalesce(x."due_on", 'infinity'::date) > (v_after ->> 0)::date) or (coalesce(x."due_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" < (v_after ->> 1)::bigint) or (coalesce(x."due_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."due_on", 'infinity'::date) asc, x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'variantId', x."variant_id", 'bomId', x."bom_id", 'quantity', x."quantity"::text, 'locationId', x."location_id", 'dueOn', x."due_on", 'status', x."status", 'producedQuantity', x."produced_quantity"::text, 'scrapQuantity', x."scrap_quantity"::text, 'outputLotId', x."output_lot_id", 'materialCost', x."material_cost"::text, 'laborCost', x."labor_cost"::text, 'currency', x."currency", 'note', x."note", 'releasedAt', x."released_at", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."due_on", 'infinity'::date))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_search is null or x."number" ilike v_search or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (coalesce(x."due_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."due_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."due_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" < (v_after ->> 1)::bigint) or (coalesce(x."due_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."due_on", 'infinity'::date) desc, x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'variantId', x."variant_id", 'bomId', x."bom_id", 'quantity', x."quantity"::text, 'locationId', x."location_id", 'dueOn', x."due_on", 'status', x."status", 'producedQuantity', x."produced_quantity"::text, 'scrapQuantity', x."scrap_quantity"::text, 'outputLotId', x."output_lot_id", 'materialCost', x."material_cost"::text, 'laborCost', x."labor_cost"::text, 'currency', x."currency", 'note', x."note", 'releasedAt', x."released_at", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_search is null or x."number" ilike v_search or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'variantId', x."variant_id", 'bomId', x."bom_id", 'quantity', x."quantity"::text, 'locationId', x."location_id", 'dueOn', x."due_on", 'status', x."status", 'producedQuantity', x."produced_quantity"::text, 'scrapQuantity', x."scrap_quantity"::text, 'outputLotId', x."output_lot_id", 'materialCost', x."material_cost"::text, 'laborCost', x."labor_cost"::text, 'currency', x."currency", 'note', x."note", 'releasedAt', x."released_at", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_search is null or x."number" ilike v_search or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'variantId', x."variant_id", 'bomId', x."bom_id", 'quantity', x."quantity"::text, 'locationId', x."location_id", 'dueOn', x."due_on", 'status', x."status", 'producedQuantity', x."produced_quantity"::text, 'scrapQuantity', x."scrap_quantity"::text, 'outputLotId', x."output_lot_id", 'materialCost', x."material_cost"::text, 'laborCost', x."labor_cost"::text, 'currency', x."currency", 'note', x."note", 'releasedAt', x."released_at", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_search is null or x."number" ilike v_search or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."sequence", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."sequence" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'variantId', x."variant_id", 'bomId', x."bom_id", 'quantity', x."quantity"::text, 'locationId', x."location_id", 'dueOn', x."due_on", 'status', x."status", 'producedQuantity', x."produced_quantity"::text, 'scrapQuantity', x."scrap_quantity"::text, 'outputLotId', x."output_lot_id", 'materialCost', x."material_cost"::text, 'laborCost', x."labor_cost"::text, 'currency', x."currency", 'note', x."note", 'releasedAt', x."released_at", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_search is null or x."number" ilike v_search or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."sequence" <= (v_after ->> 0)::bigint and ((x."sequence" < (v_after ->> 0)::bigint) or (x."sequence" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."production_orders" x
      where x."tenant_id" = list_production_orders.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (v_search is null or x."number" ilike v_search or coalesce(x."note", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_putaway_rules (
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
  v_filters jsonb := coalesce(list_putaway_rules.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 1000), 1), 1000);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_putaway_rules.tenant is not null and coalesce(better_supabase.can('tenant', list_putaway_rules.tenant, 'warehouse.read'), false))) then
    raise exception 'not allowed to read putaway rules' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('active') then
      raise exception 'facet is one of active' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'active' then (x."active"::text)::text end) as v
      from "better_supabase"."putaway_rules" x
      where x."tenant_id" = list_putaway_rules.tenant
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id"::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
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
      select 1 from "better_supabase"."putaway_rules" x
      where x."tenant_id" = list_putaway_rules.tenant
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id"::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('priority', 'createdAt') then
    raise exception 'sort is one of priority, createdAt' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id",
    'binId', x."bin_id", 'variantId', x."variant_id", 'priority', x."priority",
    'maxQuantity', x."max_quantity"::text, 'active', x."active", 'createdAt', x."created_at") as j, jsonb_build_array((x."priority")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."putaway_rules" x
      where x."tenant_id" = list_putaway_rules.tenant
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id"::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_after is null or (x."priority", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."priority" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id",
    'binId', x."bin_id", 'variantId', x."variant_id", 'priority', x."priority",
    'maxQuantity', x."max_quantity"::text, 'active', x."active", 'createdAt', x."created_at") as j, jsonb_build_array((x."priority")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."putaway_rules" x
      where x."tenant_id" = list_putaway_rules.tenant
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id"::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_after is null or (x."priority" <= (v_after ->> 0)::integer and ((x."priority" < (v_after ->> 0)::integer) or (x."priority" = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by x."priority" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'priority' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id",
    'binId', x."bin_id", 'variantId', x."variant_id", 'priority', x."priority",
    'maxQuantity', x."max_quantity"::text, 'active', x."active", 'createdAt', x."created_at") as j, jsonb_build_array((x."priority")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."putaway_rules" x
      where x."tenant_id" = list_putaway_rules.tenant
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id"::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_after is null or (x."priority", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."priority" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'priority' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id",
    'binId', x."bin_id", 'variantId', x."variant_id", 'priority', x."priority",
    'maxQuantity', x."max_quantity"::text, 'active', x."active", 'createdAt', x."created_at") as j, jsonb_build_array((x."priority")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."putaway_rules" x
      where x."tenant_id" = list_putaway_rules.tenant
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id"::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_after is null or (x."priority" <= (v_after ->> 0)::integer and ((x."priority" < (v_after ->> 0)::integer) or (x."priority" = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by x."priority" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id",
    'binId', x."bin_id", 'variantId', x."variant_id", 'priority', x."priority",
    'maxQuantity', x."max_quantity"::text, 'active', x."active", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."putaway_rules" x
      where x."tenant_id" = list_putaway_rules.tenant
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id"::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id",
    'binId', x."bin_id", 'variantId', x."variant_id", 'priority', x."priority",
    'maxQuantity', x."max_quantity"::text, 'active', x."active", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."putaway_rules" x
      where x."tenant_id" = list_putaway_rules.tenant
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id"::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."putaway_rules" x
      where x."tenant_id" = list_putaway_rules.tenant
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id"::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_rfqs (
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
  v_filters jsonb := coalesce(list_rfqs.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_rfqs.tenant is not null and coalesce(better_supabase.can('tenant', list_rfqs.tenant, 'rfqs.read'), false))) then
    raise exception 'not allowed to read requests for quotation' using errcode = '42501', hint = 'RFQ_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'RFQ_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."rfqs" x
      where x."tenant_id" = list_rfqs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search)
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
      select 1 from "better_supabase"."rfqs" x
      where x."tenant_id" = list_rfqs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('number', 'dueAt') then
    raise exception 'sort is one of number, dueAt' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'title', x."title", 'status', x."status", 'currency', x."currency", 'dueAt', x."due_at", 'notes', x."notes", 'awardedQuoteId', x."awarded_quote_id", 'purchaseOrderId', x."purchase_order_id", 'cancelReason', x."cancel_reason", 'openedAt', x."opened_at", 'closedAt', x."closed_at", 'awardedAt', x."awarded_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."rfqs" x
      where x."tenant_id" = list_rfqs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search)
        and (v_after is null or (x."sequence", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."sequence" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'title', x."title", 'status', x."status", 'currency', x."currency", 'dueAt', x."due_at", 'notes', x."notes", 'awardedQuoteId', x."awarded_quote_id", 'purchaseOrderId', x."purchase_order_id", 'cancelReason', x."cancel_reason", 'openedAt', x."opened_at", 'closedAt', x."closed_at", 'awardedAt', x."awarded_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."rfqs" x
      where x."tenant_id" = list_rfqs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search)
        and (v_after is null or (x."sequence" <= (v_after ->> 0)::bigint and ((x."sequence" < (v_after ->> 0)::bigint) or (x."sequence" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'title', x."title", 'status', x."status", 'currency', x."currency", 'dueAt', x."due_at", 'notes', x."notes", 'awardedQuoteId', x."awarded_quote_id", 'purchaseOrderId', x."purchase_order_id", 'cancelReason', x."cancel_reason", 'openedAt', x."opened_at", 'closedAt', x."closed_at", 'awardedAt', x."awarded_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."rfqs" x
      where x."tenant_id" = list_rfqs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search)
        and (v_after is null or (x."sequence", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."sequence" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'title', x."title", 'status', x."status", 'currency', x."currency", 'dueAt', x."due_at", 'notes', x."notes", 'awardedQuoteId', x."awarded_quote_id", 'purchaseOrderId', x."purchase_order_id", 'cancelReason', x."cancel_reason", 'openedAt', x."opened_at", 'closedAt', x."closed_at", 'awardedAt', x."awarded_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."rfqs" x
      where x."tenant_id" = list_rfqs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search)
        and (v_after is null or (x."sequence" <= (v_after ->> 0)::bigint and ((x."sequence" < (v_after ->> 0)::bigint) or (x."sequence" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'title', x."title", 'status', x."status", 'currency', x."currency", 'dueAt', x."due_at", 'notes', x."notes", 'awardedQuoteId', x."awarded_quote_id", 'purchaseOrderId', x."purchase_order_id", 'cancelReason', x."cancel_reason", 'openedAt', x."opened_at", 'closedAt', x."closed_at", 'awardedAt', x."awarded_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."rfqs" x
      where x."tenant_id" = list_rfqs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search)
        and (v_after is null or (coalesce(x."due_at", 'infinity'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(x."due_at", 'infinity'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(x."due_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."sequence" < (v_after ->> 1)::bigint) or (coalesce(x."due_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."due_at", 'infinity'::timestamptz) asc, x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'title', x."title", 'status', x."status", 'currency', x."currency", 'dueAt', x."due_at", 'notes', x."notes", 'awardedQuoteId', x."awarded_quote_id", 'purchaseOrderId', x."purchase_order_id", 'cancelReason', x."cancel_reason", 'openedAt', x."opened_at", 'closedAt', x."closed_at", 'awardedAt', x."awarded_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."rfqs" x
      where x."tenant_id" = list_rfqs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search)
        and (v_after is null or (coalesce(x."due_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."due_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."due_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."sequence" < (v_after ->> 1)::bigint) or (coalesce(x."due_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."due_at", 'infinity'::timestamptz) desc, x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."rfqs" x
      where x."tenant_id" = list_rfqs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_samples (
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
  v_filters jsonb := coalesce(list_samples.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_samples.tenant is not null and coalesce(better_supabase.can('tenant', list_samples.tenant, 'lims.read'), false))) then
    raise exception 'not allowed to read samples' using errcode = '42501', hint = 'LIMS_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'kind') then
      raise exception 'facet is one of status, kind' using errcode = '22023', hint = 'LIMS_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'kind' then (x."kind")::text end) as v
      from "better_supabase"."lims_samples" x
      where x."tenant_id" = list_samples.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search or coalesce(x."lot", '') ilike v_search)
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
      select 1 from "better_supabase"."lims_samples" x
      where x."tenant_id" = list_samples.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search or coalesce(x."lot", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('number', 'receivedOn') then
    raise exception 'sort is one of number, receivedOn' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'title', x."title", 'kind', x."kind", 'lot', x."lot", 'receivedOn', x."received_on", 'status', x."status", 'notes', x."notes", 'rejectionReason', x."rejection_reason", 'completedAt', x."completed_at", 'releasedAt', x."released_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."lims_samples" x
      where x."tenant_id" = list_samples.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search or coalesce(x."lot", '') ilike v_search)
        and (v_after is null or (x."sequence", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."sequence" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'title', x."title", 'kind', x."kind", 'lot', x."lot", 'receivedOn', x."received_on", 'status', x."status", 'notes', x."notes", 'rejectionReason', x."rejection_reason", 'completedAt', x."completed_at", 'releasedAt', x."released_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."lims_samples" x
      where x."tenant_id" = list_samples.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search or coalesce(x."lot", '') ilike v_search)
        and (v_after is null or (x."sequence" <= (v_after ->> 0)::bigint and ((x."sequence" < (v_after ->> 0)::bigint) or (x."sequence" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'title', x."title", 'kind', x."kind", 'lot', x."lot", 'receivedOn', x."received_on", 'status', x."status", 'notes', x."notes", 'rejectionReason', x."rejection_reason", 'completedAt', x."completed_at", 'releasedAt', x."released_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."lims_samples" x
      where x."tenant_id" = list_samples.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search or coalesce(x."lot", '') ilike v_search)
        and (v_after is null or (x."sequence", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."sequence" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'title', x."title", 'kind', x."kind", 'lot', x."lot", 'receivedOn', x."received_on", 'status', x."status", 'notes', x."notes", 'rejectionReason', x."rejection_reason", 'completedAt', x."completed_at", 'releasedAt', x."released_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."lims_samples" x
      where x."tenant_id" = list_samples.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search or coalesce(x."lot", '') ilike v_search)
        and (v_after is null or (x."sequence" <= (v_after ->> 0)::bigint and ((x."sequence" < (v_after ->> 0)::bigint) or (x."sequence" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'receivedOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'title', x."title", 'kind', x."kind", 'lot', x."lot", 'receivedOn', x."received_on", 'status', x."status", 'notes', x."notes", 'rejectionReason', x."rejection_reason", 'completedAt', x."completed_at", 'releasedAt', x."released_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."received_on")::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."lims_samples" x
      where x."tenant_id" = list_samples.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search or coalesce(x."lot", '') ilike v_search)
        and (v_after is null or (x."received_on" >= (v_after ->> 0)::date and ((x."received_on" > (v_after ->> 0)::date) or (x."received_on" = (v_after ->> 0)::date and x."sequence" < (v_after ->> 1)::bigint) or (x."received_on" = (v_after ->> 0)::date and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by x."received_on" asc, x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'receivedOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'title', x."title", 'kind', x."kind", 'lot', x."lot", 'receivedOn', x."received_on", 'status', x."status", 'notes', x."notes", 'rejectionReason', x."rejection_reason", 'completedAt', x."completed_at", 'releasedAt', x."released_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."received_on")::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."lims_samples" x
      where x."tenant_id" = list_samples.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search or coalesce(x."lot", '') ilike v_search)
        and (v_after is null or (x."received_on" <= (v_after ->> 0)::date and ((x."received_on" < (v_after ->> 0)::date) or (x."received_on" = (v_after ->> 0)::date and x."sequence" < (v_after ->> 1)::bigint) or (x."received_on" = (v_after ->> 0)::date and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by x."received_on" desc, x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."lims_samples" x
      where x."tenant_id" = list_samples.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."number" ilike v_search or x."title" ilike v_search or coalesce(x."lot", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_shipments (
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
  v_filters jsonb := coalesce(list_shipments.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 500);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_shipments.tenant, 'shipments.read'), false)) then
    raise exception 'not allowed to read shipments' using errcode = '42501', hint = 'SHIPMENT_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'carrier') then
      raise exception 'facet is one of status, carrier' using errcode = '22023', hint = 'SHIPMENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'carrier' then (x."carrier")::text end) as v
      from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_search is null or x."reference" ilike v_search or coalesce(x."tracking_number", '') ilike v_search)
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
      select 1 from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_search is null or x."reference" ilike v_search or coalesce(x."tracking_number", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'deliveredAt') then
    raise exception 'sort is one of createdAt, deliveredAt' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_search is null or x."reference" ilike v_search or coalesce(x."tracking_number", '') ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_search is null or x."reference" ilike v_search or coalesce(x."tracking_number", '') ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_search is null or x."reference" ilike v_search or coalesce(x."tracking_number", '') ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_search is null or x."reference" ilike v_search or coalesce(x."tracking_number", '') ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'deliveredAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_search is null or x."reference" ilike v_search or coalesce(x."tracking_number", '') ilike v_search)
        and (v_after is null or (coalesce(x."delivered_at", 'infinity'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(x."delivered_at", 'infinity'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(x."delivered_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."delivered_at", 'infinity'::timestamptz) asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'deliveredAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SHIPMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'reference', x."reference", 'status', x."status", 'from', x."from_address", 'to', x."to_address", 'direction', x."direction", 'fromLocationId', x."from_location_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'carrier', x."carrier", 'service', x."service", 'trackingNumber', x."tracking_number", 'trackingUrl', x."tracking_url", 'labelId', x."label_id", 'labelUrl', x."label_url", 'labelFormat', x."label_format", 'labelCost', x."label_cost"::text, 'currency', x."currency", 'labeledAt', x."labeled_at", 'deliveredAt', x."delivered_at", 'deliveredTo', x."delivered_to", 'proofReference', x."proof_reference", 'proofAttachmentId', x."proof_attachment_id", 'proofRecordedAt', x."proof_recorded_at", 'cancelledAt', x."cancelled_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'packages', (select coalesce(jsonb_agg(jsonb_build_object('id', pk."id", 'position', pk."position", 'weightGrams', pk."weight_grams", 'lengthMm', pk."length_mm", 'widthMm', pk."width_mm", 'heightMm', pk."height_mm", 'reference', pk."reference") order by pk."position"), '[]'::jsonb) from "better_supabase"."shipment_packages" pk where pk."shipment_id" = x."id"), 'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', sl."id", 'position', sl."position", 'direction', sl."direction",
    'variantId', sl."variant_id", 'locationId', sl."location_id", 'quantity', sl."quantity"::text, 'allocationId', sl."allocation_id",
    'detail', sl."detail", 'disposition', sl."disposition", 'movementId', sl."movement_id", 'movedAt', sl."moved_at")
    order by sl."position"), '[]'::jsonb) from "better_supabase"."shipment_lines" sl where sl."shipment_id" = x."id")) as j, jsonb_build_array((coalesce(x."delivered_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_search is null or x."reference" ilike v_search or coalesce(x."tracking_number", '') ilike v_search)
        and (v_after is null or (coalesce(x."delivered_at", 'infinity'::timestamptz), x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."delivered_at", 'infinity'::timestamptz) desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."shipments" x
      where x."tenant_id" = list_shipments.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'carrier' is not null and jsonb_typeof(v_filters -> 'carrier') <> 'null' and not (jsonb_typeof(v_filters -> 'carrier') = 'array' and jsonb_array_length(v_filters -> 'carrier') = 0)) or x."carrier" = any((case when jsonb_typeof(v_filters -> 'carrier') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'carrier')) else array[v_filters ->> 'carrier'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (not v_filters ? 'subjectType' or (x."subject_type" = v_filters ->> 'subjectType' and x."subject_id" = v_filters ->> 'subjectId'))
        and (nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '') is null or x."created_at" < nullif(coalesce(v_filters #>> '{before,0}', v_filters ->> 'before'), '')::timestamptz)
        and (v_search is null or x."reference" ilike v_search or coalesce(x."tracking_number", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_till_sessions (
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
  v_filters jsonb := coalesce(list_till_sessions.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_till_sessions.tenant is not null and coalesce(better_supabase.can('tenant', list_till_sessions.tenant, 'tills.read'), false))) then
    raise exception 'not allowed to read till sessions' using errcode = '42501', hint = 'TILL_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'tillId') then
      raise exception 'facet is one of status, tillId' using errcode = '22023', hint = 'TILL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'tillId' then (x."till_id")::text end) as v
      from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."notes", '') ilike v_search)
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
      select 1 from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."notes", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('openedAt', 'closedAt') then
    raise exception 'sort is one of openedAt, closedAt' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tillId', x."till_id", 'organizationId', x."tenant_id", 'status', x."status", 'openingFloat', x."opening_float"::text, 'expected', (select (x."opening_float" + coalesce(sum(case when bm."kind" in ('cash_sale', 'cash_in') then bm."amount" else -bm."amount" end), 0))::text from "better_supabase"."till_movements" bm where bm."session_id" = x."id"), 'currency', (select bt."currency" from "better_supabase"."tills" bt where bt."id" = x."till_id"), 'openedBy', x."opened_by", 'openedAt', x."opened_at", 'closedBy', x."closed_by", 'closedAt', x."closed_at", 'notes', x."notes") as j, jsonb_build_array((x."opened_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."notes", '') ilike v_search)
        and (v_after is null or (x."opened_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."opened_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tillId', x."till_id", 'organizationId', x."tenant_id", 'status', x."status", 'openingFloat', x."opening_float"::text, 'expected', (select (x."opening_float" + coalesce(sum(case when bm."kind" in ('cash_sale', 'cash_in') then bm."amount" else -bm."amount" end), 0))::text from "better_supabase"."till_movements" bm where bm."session_id" = x."id"), 'currency', (select bt."currency" from "better_supabase"."tills" bt where bt."id" = x."till_id"), 'openedBy', x."opened_by", 'openedAt', x."opened_at", 'closedBy', x."closed_by", 'closedAt', x."closed_at", 'notes', x."notes") as j, jsonb_build_array((x."opened_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."notes", '') ilike v_search)
        and (v_after is null or (x."opened_at" <= (v_after ->> 0)::timestamptz and ((x."opened_at" < (v_after ->> 0)::timestamptz) or (x."opened_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."opened_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'openedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tillId', x."till_id", 'organizationId', x."tenant_id", 'status', x."status", 'openingFloat', x."opening_float"::text, 'expected', (select (x."opening_float" + coalesce(sum(case when bm."kind" in ('cash_sale', 'cash_in') then bm."amount" else -bm."amount" end), 0))::text from "better_supabase"."till_movements" bm where bm."session_id" = x."id"), 'currency', (select bt."currency" from "better_supabase"."tills" bt where bt."id" = x."till_id"), 'openedBy', x."opened_by", 'openedAt', x."opened_at", 'closedBy', x."closed_by", 'closedAt', x."closed_at", 'notes', x."notes") as j, jsonb_build_array((x."opened_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."notes", '') ilike v_search)
        and (v_after is null or (x."opened_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."opened_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'openedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tillId', x."till_id", 'organizationId', x."tenant_id", 'status', x."status", 'openingFloat', x."opening_float"::text, 'expected', (select (x."opening_float" + coalesce(sum(case when bm."kind" in ('cash_sale', 'cash_in') then bm."amount" else -bm."amount" end), 0))::text from "better_supabase"."till_movements" bm where bm."session_id" = x."id"), 'currency', (select bt."currency" from "better_supabase"."tills" bt where bt."id" = x."till_id"), 'openedBy', x."opened_by", 'openedAt', x."opened_at", 'closedBy', x."closed_by", 'closedAt', x."closed_at", 'notes', x."notes") as j, jsonb_build_array((x."opened_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."notes", '') ilike v_search)
        and (v_after is null or (x."opened_at" <= (v_after ->> 0)::timestamptz and ((x."opened_at" < (v_after ->> 0)::timestamptz) or (x."opened_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."opened_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'closedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tillId', x."till_id", 'organizationId', x."tenant_id", 'status', x."status", 'openingFloat', x."opening_float"::text, 'expected', (select (x."opening_float" + coalesce(sum(case when bm."kind" in ('cash_sale', 'cash_in') then bm."amount" else -bm."amount" end), 0))::text from "better_supabase"."till_movements" bm where bm."session_id" = x."id"), 'currency', (select bt."currency" from "better_supabase"."tills" bt where bt."id" = x."till_id"), 'openedBy', x."opened_by", 'openedAt', x."opened_at", 'closedBy', x."closed_by", 'closedAt', x."closed_at", 'notes', x."notes") as j, jsonb_build_array((coalesce(x."closed_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."notes", '') ilike v_search)
        and (v_after is null or (coalesce(x."closed_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."closed_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'closedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tillId', x."till_id", 'organizationId', x."tenant_id", 'status', x."status", 'openingFloat', x."opening_float"::text, 'expected', (select (x."opening_float" + coalesce(sum(case when bm."kind" in ('cash_sale', 'cash_in') then bm."amount" else -bm."amount" end), 0))::text from "better_supabase"."till_movements" bm where bm."session_id" = x."id"), 'currency', (select bt."currency" from "better_supabase"."tills" bt where bt."id" = x."till_id"), 'openedBy', x."opened_by", 'openedAt', x."opened_at", 'closedBy', x."closed_by", 'closedAt', x."closed_at", 'notes', x."notes") as j, jsonb_build_array((coalesce(x."closed_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."notes", '') ilike v_search)
        and (v_after is null or (coalesce(x."closed_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."closed_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."closed_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."closed_at", 'infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."notes", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_tills (
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
  v_filters jsonb := coalesce(list_tills.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_tills.tenant is not null and coalesce(better_supabase.can('tenant', list_tills.tenant, 'tills.read'), false))) then
    raise exception 'not allowed to read tills' using errcode = '42501', hint = 'TILL_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('currency') then
      raise exception 'facet is one of currency' using errcode = '22023', hint = 'TILL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'currency' then (x."currency")::text end) as v
      from "better_supabase"."tills" x
      where x."tenant_id" = list_tills.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or v_filters ->> 'archived' = 'true' or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
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
      select 1 from "better_supabase"."tills" x
      where x."tenant_id" = list_tills.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or v_filters ->> 'archived' = 'true' or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt') then
    raise exception 'sort is one of name, createdAt' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'currency', x."currency", 'accountId', x."account_id", 'location', x."location", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tills" x
      where x."tenant_id" = list_tills.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or v_filters ->> 'archived' = 'true' or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'currency', x."currency", 'accountId', x."account_id", 'location', x."location", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tills" x
      where x."tenant_id" = list_tills.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or v_filters ->> 'archived' = 'true' or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'currency', x."currency", 'accountId', x."account_id", 'location', x."location", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tills" x
      where x."tenant_id" = list_tills.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or v_filters ->> 'archived' = 'true' or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'currency', x."currency", 'accountId', x."account_id", 'location', x."location", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tills" x
      where x."tenant_id" = list_tills.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or v_filters ->> 'archived' = 'true' or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'currency', x."currency", 'accountId', x."account_id", 'location', x."location", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tills" x
      where x."tenant_id" = list_tills.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or v_filters ->> 'archived' = 'true' or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'currency', x."currency", 'accountId', x."account_id", 'location', x."location", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tills" x
      where x."tenant_id" = list_tills.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or v_filters ->> 'archived' = 'true' or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."tills" x
      where x."tenant_id" = list_tills.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or v_filters ->> 'archived' = 'true' or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_boms (
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
  v_filters jsonb := coalesce(page_boms.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_boms.tenant is not null and coalesce(better_supabase.can('tenant', page_boms.tenant, 'manufacturing.read'), false))) then
    raise exception 'not allowed to read bills of materials' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."boms" x
      where x."tenant_id" = page_boms.tenant
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."note", '') ilike v_search)
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
      select 1 from "better_supabase"."boms" x
      where x."tenant_id" = page_boms.tenant
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."note", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('variant', 'createdAt', 'activatedAt') then
    raise exception 'sort is one of variant, createdAt, activatedAt' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'variantId', x."variant_id", 'version', x."version", 'status', x."status", 'quantity', x."quantity"::text, 'note', x."note", 'activatedAt', x."activated_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."variant_id")::text, (x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."boms" x
      where x."tenant_id" = page_boms.tenant
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."variant_id" >= (v_after ->> 0)::uuid and ((x."variant_id" > (v_after ->> 0)::uuid) or (x."variant_id" = (v_after ->> 0)::uuid and x."version" < (v_after ->> 1)::integer) or (x."variant_id" = (v_after ->> 0)::uuid and x."version" = (v_after ->> 1)::integer and x."id" > (v_after ->> 2)::uuid))))
      order by x."variant_id" asc, x."version" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'variantId', x."variant_id", 'version', x."version", 'status', x."status", 'quantity', x."quantity"::text, 'note', x."note", 'activatedAt', x."activated_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."variant_id")::text, (x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."boms" x
      where x."tenant_id" = page_boms.tenant
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."variant_id" <= (v_after ->> 0)::uuid and ((x."variant_id" < (v_after ->> 0)::uuid) or (x."variant_id" = (v_after ->> 0)::uuid and x."version" < (v_after ->> 1)::integer) or (x."variant_id" = (v_after ->> 0)::uuid and x."version" = (v_after ->> 1)::integer and x."id" > (v_after ->> 2)::uuid))))
      order by x."variant_id" desc, x."version" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'variant' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'variantId', x."variant_id", 'version', x."version", 'status', x."status", 'quantity', x."quantity"::text, 'note', x."note", 'activatedAt', x."activated_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."variant_id")::text, (x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."boms" x
      where x."tenant_id" = page_boms.tenant
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."variant_id" >= (v_after ->> 0)::uuid and ((x."variant_id" > (v_after ->> 0)::uuid) or (x."variant_id" = (v_after ->> 0)::uuid and x."version" < (v_after ->> 1)::integer) or (x."variant_id" = (v_after ->> 0)::uuid and x."version" = (v_after ->> 1)::integer and x."id" > (v_after ->> 2)::uuid))))
      order by x."variant_id" asc, x."version" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'variant' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'variantId', x."variant_id", 'version', x."version", 'status', x."status", 'quantity', x."quantity"::text, 'note', x."note", 'activatedAt', x."activated_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."variant_id")::text, (x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."boms" x
      where x."tenant_id" = page_boms.tenant
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."variant_id" <= (v_after ->> 0)::uuid and ((x."variant_id" < (v_after ->> 0)::uuid) or (x."variant_id" = (v_after ->> 0)::uuid and x."version" < (v_after ->> 1)::integer) or (x."variant_id" = (v_after ->> 0)::uuid and x."version" = (v_after ->> 1)::integer and x."id" > (v_after ->> 2)::uuid))))
      order by x."variant_id" desc, x."version" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'variantId', x."variant_id", 'version', x."version", 'status', x."status", 'quantity', x."quantity"::text, 'note', x."note", 'activatedAt', x."activated_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."boms" x
      where x."tenant_id" = page_boms.tenant
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'variantId', x."variant_id", 'version', x."version", 'status', x."status", 'quantity', x."quantity"::text, 'note', x."note", 'activatedAt', x."activated_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."boms" x
      where x."tenant_id" = page_boms.tenant
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'activatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'variantId', x."variant_id", 'version', x."version", 'status', x."status", 'quantity', x."quantity"::text, 'note', x."note", 'activatedAt', x."activated_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."activated_at", '-infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."boms" x
      where x."tenant_id" = page_boms.tenant
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (coalesce(x."activated_at", '-infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."activated_at", '-infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'activatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'variantId', x."variant_id", 'version', x."version", 'status', x."status", 'quantity', x."quantity"::text, 'note', x."note", 'activatedAt', x."activated_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."activated_at", '-infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."boms" x
      where x."tenant_id" = page_boms.tenant
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."note", '') ilike v_search)
        and (v_after is null or (coalesce(x."activated_at", '-infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."activated_at", '-infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."activated_at", '-infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."activated_at", '-infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."boms" x
      where x."tenant_id" = page_boms.tenant
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or coalesce(x."note", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_count_plans (
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
  v_filters jsonb := coalesce(page_count_plans.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_count_plans.tenant is not null and coalesce(better_supabase.can('tenant', page_count_plans.tenant, 'warehouse.read'), false))) then
    raise exception 'not allowed to read count plans' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('active') then
      raise exception 'facet is one of active' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'active' then (x."active"::text)::text end) as v
      from "better_supabase"."count_plans" x
      where x."tenant_id" = page_count_plans.tenant
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
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
      select 1 from "better_supabase"."count_plans" x
      where x."tenant_id" = page_count_plans.tenant
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('nextRunOn', 'name') then
    raise exception 'sort is one of nextRunOn, name' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'locationId', x."location_id", 'everyDays', x."every_days", 'variantIds', to_jsonb(coalesce(x."variant_ids", '{}'::uuid[])), 'varianceLimitPct', x."variance_limit_pct"::text, 'nextRunOn', x."next_run_on", 'lastRunAt', x."last_run_at", 'lastCountId', x."last_count_id", 'active', x."active", 'createdAt', x."created_at") as j, jsonb_build_array((coalesce(x."next_run_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."count_plans" x
      where x."tenant_id" = page_count_plans.tenant
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (coalesce(x."next_run_on", 'infinity'::date), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."next_run_on", 'infinity'::date) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'locationId', x."location_id", 'everyDays', x."every_days", 'variantIds', to_jsonb(coalesce(x."variant_ids", '{}'::uuid[])), 'varianceLimitPct', x."variance_limit_pct"::text, 'nextRunOn', x."next_run_on", 'lastRunAt', x."last_run_at", 'lastCountId', x."last_count_id", 'active', x."active", 'createdAt', x."created_at") as j, jsonb_build_array((coalesce(x."next_run_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."count_plans" x
      where x."tenant_id" = page_count_plans.tenant
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (coalesce(x."next_run_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."next_run_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."next_run_on", 'infinity'::date) = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."next_run_on", 'infinity'::date) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'nextRunOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'locationId', x."location_id", 'everyDays', x."every_days", 'variantIds', to_jsonb(coalesce(x."variant_ids", '{}'::uuid[])), 'varianceLimitPct', x."variance_limit_pct"::text, 'nextRunOn', x."next_run_on", 'lastRunAt', x."last_run_at", 'lastCountId', x."last_count_id", 'active', x."active", 'createdAt', x."created_at") as j, jsonb_build_array((coalesce(x."next_run_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."count_plans" x
      where x."tenant_id" = page_count_plans.tenant
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (coalesce(x."next_run_on", 'infinity'::date), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."next_run_on", 'infinity'::date) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'nextRunOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'locationId', x."location_id", 'everyDays', x."every_days", 'variantIds', to_jsonb(coalesce(x."variant_ids", '{}'::uuid[])), 'varianceLimitPct', x."variance_limit_pct"::text, 'nextRunOn', x."next_run_on", 'lastRunAt', x."last_run_at", 'lastCountId', x."last_count_id", 'active', x."active", 'createdAt', x."created_at") as j, jsonb_build_array((coalesce(x."next_run_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."count_plans" x
      where x."tenant_id" = page_count_plans.tenant
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (coalesce(x."next_run_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."next_run_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."next_run_on", 'infinity'::date) = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."next_run_on", 'infinity'::date) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'locationId', x."location_id", 'everyDays', x."every_days", 'variantIds', to_jsonb(coalesce(x."variant_ids", '{}'::uuid[])), 'varianceLimitPct', x."variance_limit_pct"::text, 'nextRunOn', x."next_run_on", 'lastRunAt', x."last_run_at", 'lastCountId', x."last_count_id", 'active', x."active", 'createdAt', x."created_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."count_plans" x
      where x."tenant_id" = page_count_plans.tenant
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'locationId', x."location_id", 'everyDays', x."every_days", 'variantIds', to_jsonb(coalesce(x."variant_ids", '{}'::uuid[])), 'varianceLimitPct', x."variance_limit_pct"::text, 'nextRunOn', x."next_run_on", 'lastRunAt', x."last_run_at", 'lastCountId', x."last_count_id", 'active', x."active", 'createdAt', x."created_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."count_plans" x
      where x."tenant_id" = page_count_plans.tenant
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."count_plans" x
      where x."tenant_id" = page_count_plans.tenant
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or x."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_lims_methods (
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
  v_filters jsonb := coalesce(page_lims_methods.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_lims_methods.tenant is not null and coalesce(better_supabase.can('tenant', page_lims_methods.tenant, 'lims.read'), false))) then
    raise exception 'not allowed to read test methods' using errcode = '42501', hint = 'LIMS_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('unit') then
      raise exception 'facet is one of unit' using errcode = '22023', hint = 'LIMS_INVALID';
    end if;
    with s as (
      select (case v_facet when 'unit' then (coalesce(x."unit", ''))::text end) as v
      from "better_supabase"."lims_methods" x
      where x."tenant_id" = page_lims_methods.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or coalesce(x."unit", '') = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."key" ilike v_search or x."name" ilike v_search)
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
      select 1 from "better_supabase"."lims_methods" x
      where x."tenant_id" = page_lims_methods.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or coalesce(x."unit", '') = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."key" ilike v_search or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('key', 'name', 'createdAt') then
    raise exception 'sort is one of key, name, createdAt' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'unit', x."unit", 'lowerLimit', x."lower_limit", 'upperLimit', x."upper_limit", 'formId', x."form_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."key"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."lims_methods" x
      where x."tenant_id" = page_lims_methods.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or coalesce(x."unit", '') = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."key" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (lower(x."key"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."key") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'unit', x."unit", 'lowerLimit', x."lower_limit", 'upperLimit', x."upper_limit", 'formId', x."form_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."key"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."lims_methods" x
      where x."tenant_id" = page_lims_methods.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or coalesce(x."unit", '') = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."key" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (lower(x."key") <= (v_after ->> 0)::text and ((lower(x."key") < (v_after ->> 0)::text) or (lower(x."key") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."key") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'unit', x."unit", 'lowerLimit', x."lower_limit", 'upperLimit', x."upper_limit", 'formId', x."form_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."key"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."lims_methods" x
      where x."tenant_id" = page_lims_methods.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or coalesce(x."unit", '') = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."key" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (lower(x."key"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."key") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'unit', x."unit", 'lowerLimit', x."lower_limit", 'upperLimit', x."upper_limit", 'formId', x."form_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."key"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."lims_methods" x
      where x."tenant_id" = page_lims_methods.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or coalesce(x."unit", '') = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."key" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (lower(x."key") <= (v_after ->> 0)::text and ((lower(x."key") < (v_after ->> 0)::text) or (lower(x."key") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."key") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'unit', x."unit", 'lowerLimit', x."lower_limit", 'upperLimit', x."upper_limit", 'formId', x."form_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."lims_methods" x
      where x."tenant_id" = page_lims_methods.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or coalesce(x."unit", '') = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."key" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'unit', x."unit", 'lowerLimit', x."lower_limit", 'upperLimit', x."upper_limit", 'formId', x."form_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."lims_methods" x
      where x."tenant_id" = page_lims_methods.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or coalesce(x."unit", '') = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."key" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'unit', x."unit", 'lowerLimit', x."lower_limit", 'upperLimit', x."upper_limit", 'formId', x."form_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."lims_methods" x
      where x."tenant_id" = page_lims_methods.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or coalesce(x."unit", '') = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."key" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'unit', x."unit", 'lowerLimit', x."lower_limit", 'upperLimit', x."upper_limit", 'formId', x."form_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."lims_methods" x
      where x."tenant_id" = page_lims_methods.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or coalesce(x."unit", '') = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."key" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."lims_methods" x
      where x."tenant_id" = page_lims_methods.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or coalesce(x."unit", '') = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."key" ilike v_search or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_maintenance_meters (
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
  v_filters jsonb := coalesce(page_maintenance_meters.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_maintenance_meters.tenant is not null and coalesce(better_supabase.can('tenant', page_maintenance_meters.tenant, 'maintenance.read'), false))) then
    raise exception 'not allowed to read maintenance' using errcode = '42501', hint = 'MAINTENANCE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('unit', 'assetId') then
      raise exception 'facet is one of unit, assetId' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'unit' then (x."unit")::text when 'assetId' then (x."asset_id"::text)::text end) as v
      from "better_supabase"."maintenance_meters" x
      where x."tenant_id" = page_maintenance_meters.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or x."unit" = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
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
      select 1 from "better_supabase"."maintenance_meters" x
      where x."tenant_id" = page_maintenance_meters.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or x."unit" = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'readAt') then
    raise exception 'sort is one of name, readAt' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'unit', x."unit", 'assetId', x."asset_id", 'reading', x."reading"::text, 'readAt', x."read_at", 'createdAt', x."created_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_meters" x
      where x."tenant_id" = page_maintenance_meters.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or x."unit" = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
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
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'unit', x."unit", 'assetId', x."asset_id", 'reading', x."reading"::text, 'readAt', x."read_at", 'createdAt', x."created_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_meters" x
      where x."tenant_id" = page_maintenance_meters.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or x."unit" = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'unit', x."unit", 'assetId', x."asset_id", 'reading', x."reading"::text, 'readAt', x."read_at", 'createdAt', x."created_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_meters" x
      where x."tenant_id" = page_maintenance_meters.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or x."unit" = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'unit', x."unit", 'assetId', x."asset_id", 'reading', x."reading"::text, 'readAt', x."read_at", 'createdAt', x."created_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_meters" x
      where x."tenant_id" = page_maintenance_meters.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or x."unit" = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'readAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'unit', x."unit", 'assetId', x."asset_id", 'reading', x."reading"::text, 'readAt', x."read_at", 'createdAt', x."created_at") as j, jsonb_build_array((coalesce(x."read_at", '-infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_meters" x
      where x."tenant_id" = page_maintenance_meters.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or x."unit" = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (coalesce(x."read_at", '-infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."read_at", '-infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'readAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MAINTENANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'unit', x."unit", 'assetId', x."asset_id", 'reading', x."reading"::text, 'readAt', x."read_at", 'createdAt', x."created_at") as j, jsonb_build_array((coalesce(x."read_at", '-infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_meters" x
      where x."tenant_id" = page_maintenance_meters.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or x."unit" = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (coalesce(x."read_at", '-infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."read_at", '-infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."read_at", '-infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."read_at", '-infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."maintenance_meters" x
      where x."tenant_id" = page_maintenance_meters.tenant
        and (not (v_filters -> 'unit' is not null and jsonb_typeof(v_filters -> 'unit') <> 'null' and not (jsonb_typeof(v_filters -> 'unit') = 'array' and jsonb_array_length(v_filters -> 'unit') = 0)) or x."unit" = any((case when jsonb_typeof(v_filters -> 'unit') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unit')) else array[v_filters ->> 'unit'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_pick_waves (
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
  v_filters jsonb := coalesce(page_pick_waves.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_pick_waves.tenant is not null and coalesce(better_supabase.can('tenant', page_pick_waves.tenant, 'warehouse.read'), false))) then
    raise exception 'not allowed to read pick waves' using errcode = '42501', hint = 'WAREHOUSE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'locationId') then
      raise exception 'facet is one of status, locationId' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'locationId' then (x."location_id"::text)::text end) as v
      from "better_supabase"."pick_waves" x
      where x."tenant_id" = page_pick_waves.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
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
      select 1 from "better_supabase"."pick_waves" x
      where x."tenant_id" = page_pick_waves.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'name') then
    raise exception 'sort is one of createdAt, name' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'locationId', x."location_id", 'status', x."status", 'releasedAt', x."released_at", 'completedAt', x."completed_at", 'createdAt', x."created_at")
      || jsonb_build_object(
        'lists', (select count(*) from "better_supabase"."pick_lists" z where z."wave_id" = x."id" and z."status" <> 'cancelled'),
        'openLists', (select count(*) from "better_supabase"."pick_lists" z where z."wave_id" = x."id" and z."status" = 'open')) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_waves" x
      where x."tenant_id" = page_pick_waves.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'locationId', x."location_id", 'status', x."status", 'releasedAt', x."released_at", 'completedAt', x."completed_at", 'createdAt', x."created_at")
      || jsonb_build_object(
        'lists', (select count(*) from "better_supabase"."pick_lists" z where z."wave_id" = x."id" and z."status" <> 'cancelled'),
        'openLists', (select count(*) from "better_supabase"."pick_lists" z where z."wave_id" = x."id" and z."status" = 'open')) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_waves" x
      where x."tenant_id" = page_pick_waves.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'locationId', x."location_id", 'status', x."status", 'releasedAt', x."released_at", 'completedAt', x."completed_at", 'createdAt', x."created_at")
      || jsonb_build_object(
        'lists', (select count(*) from "better_supabase"."pick_lists" z where z."wave_id" = x."id" and z."status" <> 'cancelled'),
        'openLists', (select count(*) from "better_supabase"."pick_lists" z where z."wave_id" = x."id" and z."status" = 'open')) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_waves" x
      where x."tenant_id" = page_pick_waves.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'locationId', x."location_id", 'status', x."status", 'releasedAt', x."released_at", 'completedAt', x."completed_at", 'createdAt', x."created_at")
      || jsonb_build_object(
        'lists', (select count(*) from "better_supabase"."pick_lists" z where z."wave_id" = x."id" and z."status" <> 'cancelled'),
        'openLists', (select count(*) from "better_supabase"."pick_lists" z where z."wave_id" = x."id" and z."status" = 'open')) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_waves" x
      where x."tenant_id" = page_pick_waves.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'locationId', x."location_id", 'status', x."status", 'releasedAt', x."released_at", 'completedAt', x."completed_at", 'createdAt', x."created_at")
      || jsonb_build_object(
        'lists', (select count(*) from "better_supabase"."pick_lists" z where z."wave_id" = x."id" and z."status" <> 'cancelled'),
        'openLists', (select count(*) from "better_supabase"."pick_lists" z where z."wave_id" = x."id" and z."status" = 'open')) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_waves" x
      where x."tenant_id" = page_pick_waves.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'locationId', x."location_id", 'status', x."status", 'releasedAt', x."released_at", 'completedAt', x."completed_at", 'createdAt', x."created_at")
      || jsonb_build_object(
        'lists', (select count(*) from "better_supabase"."pick_lists" z where z."wave_id" = x."id" and z."status" <> 'cancelled'),
        'openLists', (select count(*) from "better_supabase"."pick_lists" z where z."wave_id" = x."id" and z."status" = 'open')) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_waves" x
      where x."tenant_id" = page_pick_waves.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."pick_waves" x
      where x."tenant_id" = page_pick_waves.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id"::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_work_centers (
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
  v_filters jsonb := coalesce(page_work_centers.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_work_centers.tenant is not null and coalesce(better_supabase.can('tenant', page_work_centers.tenant, 'manufacturing.read'), false))) then
    raise exception 'not allowed to read work centers' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('currency') then
      raise exception 'facet is one of currency' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
    end if;
    with s as (
      select (case v_facet when 'currency' then (x."currency")::text end) as v
      from "better_supabase"."work_centers" x
      where x."tenant_id" = page_work_centers.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
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
      select 1 from "better_supabase"."work_centers" x
      where x."tenant_id" = page_work_centers.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt') then
    raise exception 'sort is one of name, createdAt' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'assetId', x."asset_id", 'hoursPerDay', x."hours_per_day"::text, 'costRate', x."cost_rate"::text, 'currency', x."currency", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_centers" x
      where x."tenant_id" = page_work_centers.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'assetId', x."asset_id", 'hoursPerDay', x."hours_per_day"::text, 'costRate', x."cost_rate"::text, 'currency', x."currency", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_centers" x
      where x."tenant_id" = page_work_centers.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'assetId', x."asset_id", 'hoursPerDay', x."hours_per_day"::text, 'costRate', x."cost_rate"::text, 'currency', x."currency", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_centers" x
      where x."tenant_id" = page_work_centers.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'assetId', x."asset_id", 'hoursPerDay', x."hours_per_day"::text, 'costRate', x."cost_rate"::text, 'currency', x."currency", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_centers" x
      where x."tenant_id" = page_work_centers.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'assetId', x."asset_id", 'hoursPerDay', x."hours_per_day"::text, 'costRate', x."cost_rate"::text, 'currency', x."currency", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_centers" x
      where x."tenant_id" = page_work_centers.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MANUFACTURING_BOM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'assetId', x."asset_id", 'hoursPerDay', x."hours_per_day"::text, 'costRate', x."cost_rate"::text, 'currency', x."currency", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_centers" x
      where x."tenant_id" = page_work_centers.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."work_centers" x
      where x."tenant_id" = page_work_centers.tenant
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."get_count_plan"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_count_plan"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_lims_method"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_lims_method"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_maintenance_meter"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_maintenance_meter"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_pick_wave"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_pick_wave"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_putaway_rule"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_putaway_rule"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_till"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_till"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_work_center"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_work_center"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_boms"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_boms"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_count_plans"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_count_plans"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_lims_methods"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_lims_methods"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_maintenance_meters"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_maintenance_meters"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_pick_waves"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_pick_waves"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_work_centers"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_work_centers"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_count_plan"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_count_plan"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_lims_method"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_lims_method"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_maintenance_meter"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_maintenance_meter"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_pick_wave"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_pick_wave"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_putaway_rule"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_putaway_rule"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_till"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_till"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_work_center"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_work_center"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_boms"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_boms"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_count_plans"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_count_plans"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_lims_methods"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_lims_methods"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_maintenance_meters"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_maintenance_meters"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_pick_waves"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_pick_waves"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_work_centers"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_work_centers"(uuid, jsonb) TO "authenticated", "service_role";
