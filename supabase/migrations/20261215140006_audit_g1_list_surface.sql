SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.get_calibration (
  calibration_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_calibration"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_maintenance_plan (
  plan_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_maintenance_plan"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_usage_right (
  right_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_usage_right"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_calibration (
  calibration_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."maintenance_calibrations";
begin
  select * into v_row from "better_supabase"."maintenance_calibrations" x where x."id" = get_calibration.calibration_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'maintenance.read'), false))) then
    raise exception 'no such calibration' using errcode = 'P0002', hint = 'MAINTENANCE_CALIBRATION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'assetId', v_row."asset_id", 'instrument', v_row."instrument", 'performedAt', v_row."performed_at", 'dueAt', v_row."due_at", 'result', v_row."result", 'reference', v_row."reference", 'performedBy', v_row."performed_by", 'qualifications', to_jsonb(v_row."qualifications"));
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

CREATE OR REPLACE FUNCTION better_supabase.get_usage_right (
  right_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."dam_usage_rights";
begin
  select * into v_row from "better_supabase"."dam_usage_rights" x where x."id" = get_usage_right.right_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dam.read'), false))) then
    raise exception 'no such usage right' using errcode = 'P0002', hint = 'DAM_USAGE_RIGHT_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'nodeId', v_row."node_id", 'licensee', v_row."licensee", 'territory', v_row."territory", 'channel', v_row."channel", 'startsOn', v_row."starts_on", 'expiresOn', v_row."expires_on", 'status', case when v_row."revoked_at" is not null then 'revoked' when v_row."starts_on" > current_date then 'upcoming' when v_row."expires_on" is not null and v_row."expires_on" < current_date then 'expired' else 'active' end, 'note', v_row."note", 'revokedAt', v_row."revoked_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_agent_mandates (
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
  v_filters jsonb := coalesce(list_agent_mandates.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_agent_mandates.tenant is not null and coalesce(better_supabase.can('tenant', list_agent_mandates.tenant, 'agent_checkout.read'), false))) then
    raise exception 'not allowed to read mandates' using errcode = '42501', hint = 'AGENT_MANDATE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'vct') then
      raise exception 'facet is one of status, vct' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'vct' then (x."vct")::text end) as v
      from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
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
      select 1 from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'expiresAt') then
    raise exception 'sort is one of createdAt, expiresAt' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sessionId', x."session_id", 'vct', x."vct", 'status', x."status", 'credential', x."credential", 'credentialHash', x."credential_hash", 'issuerKid', x."issuer_kid", 'subject', x."subject", 'expiresAt', x."expires_at", 'expired', (x."status" = 'active' and x."expires_at" <= now()), 'consumedAt', x."consumed_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sessionId', x."session_id", 'vct', x."vct", 'status', x."status", 'credential', x."credential", 'credentialHash', x."credential_hash", 'issuerKid', x."issuer_kid", 'subject', x."subject", 'expiresAt', x."expires_at", 'expired', (x."status" = 'active' and x."expires_at" <= now()), 'consumedAt', x."consumed_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sessionId', x."session_id", 'vct', x."vct", 'status', x."status", 'credential', x."credential", 'credentialHash', x."credential_hash", 'issuerKid', x."issuer_kid", 'subject', x."subject", 'expiresAt', x."expires_at", 'expired', (x."status" = 'active' and x."expires_at" <= now()), 'consumedAt', x."consumed_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sessionId', x."session_id", 'vct', x."vct", 'status', x."status", 'credential', x."credential", 'credentialHash', x."credential_hash", 'issuerKid', x."issuer_kid", 'subject', x."subject", 'expiresAt', x."expires_at", 'expired', (x."status" = 'active' and x."expires_at" <= now()), 'consumedAt', x."consumed_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'expiresAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sessionId', x."session_id", 'vct', x."vct", 'status', x."status", 'credential', x."credential", 'credentialHash', x."credential_hash", 'issuerKid', x."issuer_kid", 'subject', x."subject", 'expiresAt', x."expires_at", 'expired', (x."status" = 'active' and x."expires_at" <= now()), 'consumedAt', x."consumed_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."expires_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
        and (v_after is null or (x."expires_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."expires_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'expiresAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_MANDATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sessionId', x."session_id", 'vct', x."vct", 'status', x."status", 'credential', x."credential", 'credentialHash', x."credential_hash", 'issuerKid', x."issuer_kid", 'subject', x."subject", 'expiresAt', x."expires_at", 'expired', (x."status" = 'active' and x."expires_at" <= now()), 'consumedAt', x."consumed_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."expires_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
        and (v_after is null or (x."expires_at" <= (v_after ->> 0)::timestamptz and ((x."expires_at" < (v_after ->> 0)::timestamptz) or (x."expires_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."expires_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."agent_mandates" x
      where x."tenant_id" = list_agent_mandates.tenant
        and (not (v_filters -> 'sessionId' is not null and jsonb_typeof(v_filters -> 'sessionId') <> 'null' and not (jsonb_typeof(v_filters -> 'sessionId') = 'array' and jsonb_array_length(v_filters -> 'sessionId') = 0)) or x."session_id"::text = any((case when jsonb_typeof(v_filters -> 'sessionId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sessionId')) else array[v_filters ->> 'sessionId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'vct' is not null and jsonb_typeof(v_filters -> 'vct') <> 'null' and not (jsonb_typeof(v_filters -> 'vct') = 'array' and jsonb_array_length(v_filters -> 'vct') = 0)) or x."vct" = any((case when jsonb_typeof(v_filters -> 'vct') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'vct')) else array[v_filters ->> 'vct'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_appraisals (
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
  v_filters jsonb := coalesce(list_appraisals.filters, '{}'::jsonb);
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
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_appraisals.tenant is not null and coalesce(better_supabase.can('tenant', list_appraisals.tenant, 'appraisals.read'), false)));
begin
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."appraisals" x
      where x."tenant_id" = list_appraisals.tenant
        and (not (v_filters -> 'cycleId' is not null and jsonb_typeof(v_filters -> 'cycleId') <> 'null' and not (jsonb_typeof(v_filters -> 'cycleId') = 'array' and jsonb_array_length(v_filters -> 'cycleId') = 0)) or x."cycle_id" = any((case when jsonb_typeof(v_filters -> 'cycleId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cycleId')) else array[v_filters ->> 'cycleId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectUserId' is not null and jsonb_typeof(v_filters -> 'subjectUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectUserId') = 'array' and jsonb_array_length(v_filters -> 'subjectUserId') = 0)) or x."appraisee_id" = any((case when jsonb_typeof(v_filters -> 'subjectUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectUserId')) else array[v_filters ->> 'subjectUserId'] end)::uuid[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or (x."appraisee_id" = auth.uid()
    or exists (select 1 from "better_supabase"."appraisal_reviews" z where z."appraisal_id" = x."id" and z."reviewer_id" = auth.uid())))
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
      select 1 from "better_supabase"."appraisals" x
      where x."tenant_id" = list_appraisals.tenant
        and (not (v_filters -> 'cycleId' is not null and jsonb_typeof(v_filters -> 'cycleId') <> 'null' and not (jsonb_typeof(v_filters -> 'cycleId') = 'array' and jsonb_array_length(v_filters -> 'cycleId') = 0)) or x."cycle_id" = any((case when jsonb_typeof(v_filters -> 'cycleId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cycleId')) else array[v_filters ->> 'cycleId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectUserId' is not null and jsonb_typeof(v_filters -> 'subjectUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectUserId') = 'array' and jsonb_array_length(v_filters -> 'subjectUserId') = 0)) or x."appraisee_id" = any((case when jsonb_typeof(v_filters -> 'subjectUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectUserId')) else array[v_filters ->> 'subjectUserId'] end)::uuid[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or (x."appraisee_id" = auth.uid()
    or exists (select 1 from "better_supabase"."appraisal_reviews" z where z."appraisal_id" = x."id" and z."reviewer_id" = auth.uid())))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'rating') then
    raise exception 'sort is one of createdAt, rating' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."appraisal_json"(x."id", v_all) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."appraisals" x
      where x."tenant_id" = list_appraisals.tenant
        and (not (v_filters -> 'cycleId' is not null and jsonb_typeof(v_filters -> 'cycleId') <> 'null' and not (jsonb_typeof(v_filters -> 'cycleId') = 'array' and jsonb_array_length(v_filters -> 'cycleId') = 0)) or x."cycle_id" = any((case when jsonb_typeof(v_filters -> 'cycleId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cycleId')) else array[v_filters ->> 'cycleId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectUserId' is not null and jsonb_typeof(v_filters -> 'subjectUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectUserId') = 'array' and jsonb_array_length(v_filters -> 'subjectUserId') = 0)) or x."appraisee_id" = any((case when jsonb_typeof(v_filters -> 'subjectUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectUserId')) else array[v_filters ->> 'subjectUserId'] end)::uuid[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or (x."appraisee_id" = auth.uid()
    or exists (select 1 from "better_supabase"."appraisal_reviews" z where z."appraisal_id" = x."id" and z."reviewer_id" = auth.uid())))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."appraisal_json"(x."id", v_all) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."appraisals" x
      where x."tenant_id" = list_appraisals.tenant
        and (not (v_filters -> 'cycleId' is not null and jsonb_typeof(v_filters -> 'cycleId') <> 'null' and not (jsonb_typeof(v_filters -> 'cycleId') = 'array' and jsonb_array_length(v_filters -> 'cycleId') = 0)) or x."cycle_id" = any((case when jsonb_typeof(v_filters -> 'cycleId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cycleId')) else array[v_filters ->> 'cycleId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectUserId' is not null and jsonb_typeof(v_filters -> 'subjectUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectUserId') = 'array' and jsonb_array_length(v_filters -> 'subjectUserId') = 0)) or x."appraisee_id" = any((case when jsonb_typeof(v_filters -> 'subjectUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectUserId')) else array[v_filters ->> 'subjectUserId'] end)::uuid[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or (x."appraisee_id" = auth.uid()
    or exists (select 1 from "better_supabase"."appraisal_reviews" z where z."appraisal_id" = x."id" and z."reviewer_id" = auth.uid())))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."appraisal_json"(x."id", v_all) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."appraisals" x
      where x."tenant_id" = list_appraisals.tenant
        and (not (v_filters -> 'cycleId' is not null and jsonb_typeof(v_filters -> 'cycleId') <> 'null' and not (jsonb_typeof(v_filters -> 'cycleId') = 'array' and jsonb_array_length(v_filters -> 'cycleId') = 0)) or x."cycle_id" = any((case when jsonb_typeof(v_filters -> 'cycleId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cycleId')) else array[v_filters ->> 'cycleId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectUserId' is not null and jsonb_typeof(v_filters -> 'subjectUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectUserId') = 'array' and jsonb_array_length(v_filters -> 'subjectUserId') = 0)) or x."appraisee_id" = any((case when jsonb_typeof(v_filters -> 'subjectUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectUserId')) else array[v_filters ->> 'subjectUserId'] end)::uuid[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or (x."appraisee_id" = auth.uid()
    or exists (select 1 from "better_supabase"."appraisal_reviews" z where z."appraisal_id" = x."id" and z."reviewer_id" = auth.uid())))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."appraisal_json"(x."id", v_all) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."appraisals" x
      where x."tenant_id" = list_appraisals.tenant
        and (not (v_filters -> 'cycleId' is not null and jsonb_typeof(v_filters -> 'cycleId') <> 'null' and not (jsonb_typeof(v_filters -> 'cycleId') = 'array' and jsonb_array_length(v_filters -> 'cycleId') = 0)) or x."cycle_id" = any((case when jsonb_typeof(v_filters -> 'cycleId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cycleId')) else array[v_filters ->> 'cycleId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectUserId' is not null and jsonb_typeof(v_filters -> 'subjectUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectUserId') = 'array' and jsonb_array_length(v_filters -> 'subjectUserId') = 0)) or x."appraisee_id" = any((case when jsonb_typeof(v_filters -> 'subjectUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectUserId')) else array[v_filters ->> 'subjectUserId'] end)::uuid[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or (x."appraisee_id" = auth.uid()
    or exists (select 1 from "better_supabase"."appraisal_reviews" z where z."appraisal_id" = x."id" and z."reviewer_id" = auth.uid())))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rating' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."appraisal_json"(x."id", v_all) as j, jsonb_build_array((coalesce(x."calibrated_rating"::numeric, x."rating", -1))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."appraisals" x
      where x."tenant_id" = list_appraisals.tenant
        and (not (v_filters -> 'cycleId' is not null and jsonb_typeof(v_filters -> 'cycleId') <> 'null' and not (jsonb_typeof(v_filters -> 'cycleId') = 'array' and jsonb_array_length(v_filters -> 'cycleId') = 0)) or x."cycle_id" = any((case when jsonb_typeof(v_filters -> 'cycleId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cycleId')) else array[v_filters ->> 'cycleId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectUserId' is not null and jsonb_typeof(v_filters -> 'subjectUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectUserId') = 'array' and jsonb_array_length(v_filters -> 'subjectUserId') = 0)) or x."appraisee_id" = any((case when jsonb_typeof(v_filters -> 'subjectUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectUserId')) else array[v_filters ->> 'subjectUserId'] end)::uuid[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or (x."appraisee_id" = auth.uid()
    or exists (select 1 from "better_supabase"."appraisal_reviews" z where z."appraisal_id" = x."id" and z."reviewer_id" = auth.uid())))
        and (v_after is null or (coalesce(x."calibrated_rating"::numeric, x."rating", -1), x."id") > ((v_after ->> 0)::numeric, (v_after ->> 1)::uuid))
      order by coalesce(x."calibrated_rating"::numeric, x."rating", -1) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rating' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."appraisal_json"(x."id", v_all) as j, jsonb_build_array((coalesce(x."calibrated_rating"::numeric, x."rating", -1))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."appraisals" x
      where x."tenant_id" = list_appraisals.tenant
        and (not (v_filters -> 'cycleId' is not null and jsonb_typeof(v_filters -> 'cycleId') <> 'null' and not (jsonb_typeof(v_filters -> 'cycleId') = 'array' and jsonb_array_length(v_filters -> 'cycleId') = 0)) or x."cycle_id" = any((case when jsonb_typeof(v_filters -> 'cycleId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cycleId')) else array[v_filters ->> 'cycleId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectUserId' is not null and jsonb_typeof(v_filters -> 'subjectUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectUserId') = 'array' and jsonb_array_length(v_filters -> 'subjectUserId') = 0)) or x."appraisee_id" = any((case when jsonb_typeof(v_filters -> 'subjectUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectUserId')) else array[v_filters ->> 'subjectUserId'] end)::uuid[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or (x."appraisee_id" = auth.uid()
    or exists (select 1 from "better_supabase"."appraisal_reviews" z where z."appraisal_id" = x."id" and z."reviewer_id" = auth.uid())))
        and (v_after is null or (coalesce(x."calibrated_rating"::numeric, x."rating", -1) <= (v_after ->> 0)::numeric and ((coalesce(x."calibrated_rating"::numeric, x."rating", -1) < (v_after ->> 0)::numeric) or (coalesce(x."calibrated_rating"::numeric, x."rating", -1) = (v_after ->> 0)::numeric and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."calibrated_rating"::numeric, x."rating", -1) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."appraisals" x
      where x."tenant_id" = list_appraisals.tenant
        and (not (v_filters -> 'cycleId' is not null and jsonb_typeof(v_filters -> 'cycleId') <> 'null' and not (jsonb_typeof(v_filters -> 'cycleId') = 'array' and jsonb_array_length(v_filters -> 'cycleId') = 0)) or x."cycle_id" = any((case when jsonb_typeof(v_filters -> 'cycleId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cycleId')) else array[v_filters ->> 'cycleId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectUserId' is not null and jsonb_typeof(v_filters -> 'subjectUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectUserId') = 'array' and jsonb_array_length(v_filters -> 'subjectUserId') = 0)) or x."appraisee_id" = any((case when jsonb_typeof(v_filters -> 'subjectUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectUserId')) else array[v_filters ->> 'subjectUserId'] end)::uuid[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or (x."appraisee_id" = auth.uid()
    or exists (select 1 from "better_supabase"."appraisal_reviews" z where z."appraisal_id" = x."id" and z."reviewer_id" = auth.uid())))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
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

CREATE OR REPLACE FUNCTION better_supabase.list_checkout_sessions (
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
  v_filters jsonb := coalesce(list_checkout_sessions.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_checkout_sessions.tenant is not null and coalesce(better_supabase.can('tenant', list_checkout_sessions.tenant, 'agent_checkout.read'), false))) then
    raise exception 'not allowed to read checkout sessions' using errcode = '42501', hint = 'CHECKOUT_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'protocol') then
      raise exception 'facet is one of status, protocol' using errcode = '22023', hint = 'CHECKOUT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'protocol' then (x."protocol")::text end) as v
      from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
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
      select 1 from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'expiresAt') then
    raise exception 'sort is one of createdAt, expiresAt' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'cartId', x."cart_id", 'protocol', x."protocol", 'status', x."status", 'buyer', x."buyer", 'orderId', x."order_id", 'expiresAt', x."expires_at", 'expired', (x."status" in ('open', 'ready') and x."expires_at" is not null and x."expires_at" <= now()), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'cartId', x."cart_id", 'protocol', x."protocol", 'status', x."status", 'buyer', x."buyer", 'orderId', x."order_id", 'expiresAt', x."expires_at", 'expired', (x."status" in ('open', 'ready') and x."expires_at" is not null and x."expires_at" <= now()), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'cartId', x."cart_id", 'protocol', x."protocol", 'status', x."status", 'buyer', x."buyer", 'orderId', x."order_id", 'expiresAt', x."expires_at", 'expired', (x."status" in ('open', 'ready') and x."expires_at" is not null and x."expires_at" <= now()), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'cartId', x."cart_id", 'protocol', x."protocol", 'status', x."status", 'buyer', x."buyer", 'orderId', x."order_id", 'expiresAt', x."expires_at", 'expired', (x."status" in ('open', 'ready') and x."expires_at" is not null and x."expires_at" <= now()), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'expiresAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'cartId', x."cart_id", 'protocol', x."protocol", 'status', x."status", 'buyer', x."buyer", 'orderId', x."order_id", 'expiresAt', x."expires_at", 'expired', (x."status" in ('open', 'ready') and x."expires_at" is not null and x."expires_at" <= now()), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."expires_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
        and (v_after is null or (coalesce(x."expires_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."expires_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'expiresAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHECKOUT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'cartId', x."cart_id", 'protocol', x."protocol", 'status', x."status", 'buyer', x."buyer", 'orderId', x."order_id", 'expiresAt', x."expires_at", 'expired', (x."status" in ('open', 'ready') and x."expires_at" is not null and x."expires_at" <= now()), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."expires_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
        and (v_after is null or (coalesce(x."expires_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."expires_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."expires_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."expires_at", 'infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."checkout_sessions" x
      where x."tenant_id" = list_checkout_sessions.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'protocol' is not null and jsonb_typeof(v_filters -> 'protocol') <> 'null' and not (jsonb_typeof(v_filters -> 'protocol') = 'array' and jsonb_array_length(v_filters -> 'protocol') = 0)) or x."protocol" = any((case when jsonb_typeof(v_filters -> 'protocol') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'protocol')) else array[v_filters ->> 'protocol'] end)::text[]))
        and (not (v_filters -> 'cartId' is not null and jsonb_typeof(v_filters -> 'cartId') <> 'null' and not (jsonb_typeof(v_filters -> 'cartId') = 'array' and jsonb_array_length(v_filters -> 'cartId') = 0)) or x."cart_id"::text = any((case when jsonb_typeof(v_filters -> 'cartId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'cartId')) else array[v_filters ->> 'cartId'] end)::text[]))
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
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
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
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
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
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
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
  elsif v_sort = 'nextDueAt' and coalesce(v_dir, 'asc') = 'desc' then
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
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
    ), '[]'::jsonb)) as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_plans" x
      where x."tenant_id" = list_maintenance_plans.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
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
    ), '[]'::jsonb)) as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_plans" x
      where x."tenant_id" = list_maintenance_plans.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
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
        and (not coalesce(nullif(coalesce(v_filters #>> '{due,0}', v_filters ->> 'due'), '') = 'true', false) or (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'kind', x."kind", 'assetId', x."asset_id", 'everyDays', x."every_days", 'meterId', x."meter_id", 'everyValue', x."every_value"::text, 'priority', x."priority", 'status', x."status", 'lastDoneAt', x."last_done_at", 'lastDoneValue', x."last_done_value"::text, 'nextDueAt', x."next_due_at", 'workOrderId', x."work_order_id", 'rrule', x."rrule", 'dtstart', x."dtstart", 'tz', x."tz", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object(
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_pick_lists (
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
  v_filters jsonb := coalesce(list_pick_lists.filters, '{}'::jsonb);
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
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_pick_lists.tenant is not null and coalesce(better_supabase.can('tenant', list_pick_lists.tenant, 'warehouse.read'), false)));
begin
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'documentType') then
      raise exception 'facet is one of status, documentType' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'documentType' then (x."document_type")::text end) as v
      from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
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
      select 1 from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'pickedAt') then
    raise exception 'sort is one of createdAt, pickedAt' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
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
    select row_number() over () as n, "better_supabase"."pick_list_json"(x."id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
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
    select row_number() over () as n, "better_supabase"."pick_list_json"(x."id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
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
    select row_number() over () as n, "better_supabase"."pick_list_json"(x."id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
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
    select row_number() over () as n, "better_supabase"."pick_list_json"(x."id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'pickedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."pick_list_json"(x."id") as j, jsonb_build_array((coalesce(x."picked_at", '-infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
        and (v_after is null or (coalesce(x."picked_at", '-infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."picked_at", '-infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'pickedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."pick_list_json"(x."id") as j, jsonb_build_array((coalesce(x."picked_at", '-infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
        and (v_after is null or (coalesce(x."picked_at", '-infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."picked_at", '-infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."picked_at", '-infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."picked_at", '-infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (not (v_filters -> 'waveId' is not null and jsonb_typeof(v_filters -> 'waveId') <> 'null' and not (jsonb_typeof(v_filters -> 'waveId') = 'array' and jsonb_array_length(v_filters -> 'waveId') = 0)) or x."wave_id" = any((case when jsonb_typeof(v_filters -> 'waveId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'waveId')) else array[v_filters ->> 'waveId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."document_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and ((v_all and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or coalesce(x."assignee_id" = auth.uid(), false))
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
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_risks (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_risks.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_risks.tenant is not null and coalesce(better_supabase.can('tenant', list_risks.tenant, 'risks.read'), false))) then
    raise exception 'not allowed to read risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'category', 'band') then
      raise exception 'facet is one of status, category, band' using errcode = '22023', hint = 'RISK_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'category' then (x."category")::text when 'band' then (x."residual_band")::text end) as v
      from "better_supabase"."risks" x
      where x."tenant_id" = list_risks.tenant
        and x."archived_at" is null
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" <> 'closed' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or x."category" = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (not (v_filters -> 'band' is not null and jsonb_typeof(v_filters -> 'band') <> 'null' and not (jsonb_typeof(v_filters -> 'band') = 'array' and jsonb_array_length(v_filters -> 'band') = 0)) or x."residual_band" = any((case when jsonb_typeof(v_filters -> 'band') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'band')) else array[v_filters ->> 'band'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or x."next_review_on" <= current_date)
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."cause" ilike v_search or x."consequence" ilike v_search)
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
      select 1 from "better_supabase"."risks" x
      where x."tenant_id" = list_risks.tenant
        and x."archived_at" is null
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" <> 'closed' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or x."category" = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (not (v_filters -> 'band' is not null and jsonb_typeof(v_filters -> 'band') <> 'null' and not (jsonb_typeof(v_filters -> 'band') = 'array' and jsonb_array_length(v_filters -> 'band') = 0)) or x."residual_band" = any((case when jsonb_typeof(v_filters -> 'band') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'band')) else array[v_filters ->> 'band'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or x."next_review_on" <= current_date)
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."cause" ilike v_search or x."consequence" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('residualScore', 'number', 'nextReviewOn') then
    raise exception 'sort is one of residualScore, number, nextReviewOn' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'matrixId', x."matrix_id", 'title', x."title", 'description', x."description", 'category', x."category", 'cause', x."cause", 'consequence', x."consequence", 'ownerId', x."owner_id", 'status', x."status", 'treatment', x."treatment", 'reviewIntervalMonths', x."review_interval_months", 'nextReviewOn', x."next_review_on", 'reviewedAt', x."reviewed_at", 'inherent', case when x."inherent_score" is null then null else jsonb_build_object('likelihood', x."inherent_likelihood", 'impact', x."inherent_impact", 'score', x."inherent_score", 'band', x."inherent_band") end, 'residual', case when x."residual_score" is null then null else jsonb_build_object('likelihood', x."residual_likelihood", 'impact', x."residual_impact", 'score', x."residual_score", 'band', x."residual_band") end, 'currentAssessmentId', x."current_assessment_id", 'closedAt', x."closed_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."residual_score", -1))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."risks" x
      where x."tenant_id" = list_risks.tenant
        and x."archived_at" is null
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" <> 'closed' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or x."category" = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (not (v_filters -> 'band' is not null and jsonb_typeof(v_filters -> 'band') <> 'null' and not (jsonb_typeof(v_filters -> 'band') = 'array' and jsonb_array_length(v_filters -> 'band') = 0)) or x."residual_band" = any((case when jsonb_typeof(v_filters -> 'band') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'band')) else array[v_filters ->> 'band'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or x."next_review_on" <= current_date)
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."cause" ilike v_search or x."consequence" ilike v_search)
        and (v_after is null or (coalesce(x."residual_score", -1), x."sequence", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::bigint, (v_after ->> 2)::uuid))
      order by coalesce(x."residual_score", -1) asc, x."sequence" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'matrixId', x."matrix_id", 'title', x."title", 'description', x."description", 'category', x."category", 'cause', x."cause", 'consequence', x."consequence", 'ownerId', x."owner_id", 'status', x."status", 'treatment', x."treatment", 'reviewIntervalMonths', x."review_interval_months", 'nextReviewOn', x."next_review_on", 'reviewedAt', x."reviewed_at", 'inherent', case when x."inherent_score" is null then null else jsonb_build_object('likelihood', x."inherent_likelihood", 'impact', x."inherent_impact", 'score', x."inherent_score", 'band', x."inherent_band") end, 'residual', case when x."residual_score" is null then null else jsonb_build_object('likelihood', x."residual_likelihood", 'impact', x."residual_impact", 'score', x."residual_score", 'band', x."residual_band") end, 'currentAssessmentId', x."current_assessment_id", 'closedAt', x."closed_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."residual_score", -1))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."risks" x
      where x."tenant_id" = list_risks.tenant
        and x."archived_at" is null
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" <> 'closed' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or x."category" = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (not (v_filters -> 'band' is not null and jsonb_typeof(v_filters -> 'band') <> 'null' and not (jsonb_typeof(v_filters -> 'band') = 'array' and jsonb_array_length(v_filters -> 'band') = 0)) or x."residual_band" = any((case when jsonb_typeof(v_filters -> 'band') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'band')) else array[v_filters ->> 'band'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or x."next_review_on" <= current_date)
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."cause" ilike v_search or x."consequence" ilike v_search)
        and (v_after is null or (coalesce(x."residual_score", -1) <= (v_after ->> 0)::integer and ((coalesce(x."residual_score", -1) < (v_after ->> 0)::integer) or (coalesce(x."residual_score", -1) = (v_after ->> 0)::integer and x."sequence" > (v_after ->> 1)::bigint) or (coalesce(x."residual_score", -1) = (v_after ->> 0)::integer and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."residual_score", -1) desc, x."sequence" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'residualScore' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'matrixId', x."matrix_id", 'title', x."title", 'description', x."description", 'category', x."category", 'cause', x."cause", 'consequence', x."consequence", 'ownerId', x."owner_id", 'status', x."status", 'treatment', x."treatment", 'reviewIntervalMonths', x."review_interval_months", 'nextReviewOn', x."next_review_on", 'reviewedAt', x."reviewed_at", 'inherent', case when x."inherent_score" is null then null else jsonb_build_object('likelihood', x."inherent_likelihood", 'impact', x."inherent_impact", 'score', x."inherent_score", 'band', x."inherent_band") end, 'residual', case when x."residual_score" is null then null else jsonb_build_object('likelihood', x."residual_likelihood", 'impact', x."residual_impact", 'score', x."residual_score", 'band', x."residual_band") end, 'currentAssessmentId', x."current_assessment_id", 'closedAt', x."closed_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."residual_score", -1))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."risks" x
      where x."tenant_id" = list_risks.tenant
        and x."archived_at" is null
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" <> 'closed' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or x."category" = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (not (v_filters -> 'band' is not null and jsonb_typeof(v_filters -> 'band') <> 'null' and not (jsonb_typeof(v_filters -> 'band') = 'array' and jsonb_array_length(v_filters -> 'band') = 0)) or x."residual_band" = any((case when jsonb_typeof(v_filters -> 'band') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'band')) else array[v_filters ->> 'band'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or x."next_review_on" <= current_date)
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."cause" ilike v_search or x."consequence" ilike v_search)
        and (v_after is null or (coalesce(x."residual_score", -1), x."sequence", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::bigint, (v_after ->> 2)::uuid))
      order by coalesce(x."residual_score", -1) asc, x."sequence" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'residualScore' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'matrixId', x."matrix_id", 'title', x."title", 'description', x."description", 'category', x."category", 'cause', x."cause", 'consequence', x."consequence", 'ownerId', x."owner_id", 'status', x."status", 'treatment', x."treatment", 'reviewIntervalMonths', x."review_interval_months", 'nextReviewOn', x."next_review_on", 'reviewedAt', x."reviewed_at", 'inherent', case when x."inherent_score" is null then null else jsonb_build_object('likelihood', x."inherent_likelihood", 'impact', x."inherent_impact", 'score', x."inherent_score", 'band', x."inherent_band") end, 'residual', case when x."residual_score" is null then null else jsonb_build_object('likelihood', x."residual_likelihood", 'impact', x."residual_impact", 'score', x."residual_score", 'band', x."residual_band") end, 'currentAssessmentId', x."current_assessment_id", 'closedAt', x."closed_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."residual_score", -1))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."risks" x
      where x."tenant_id" = list_risks.tenant
        and x."archived_at" is null
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" <> 'closed' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or x."category" = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (not (v_filters -> 'band' is not null and jsonb_typeof(v_filters -> 'band') <> 'null' and not (jsonb_typeof(v_filters -> 'band') = 'array' and jsonb_array_length(v_filters -> 'band') = 0)) or x."residual_band" = any((case when jsonb_typeof(v_filters -> 'band') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'band')) else array[v_filters ->> 'band'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or x."next_review_on" <= current_date)
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."cause" ilike v_search or x."consequence" ilike v_search)
        and (v_after is null or (coalesce(x."residual_score", -1) <= (v_after ->> 0)::integer and ((coalesce(x."residual_score", -1) < (v_after ->> 0)::integer) or (coalesce(x."residual_score", -1) = (v_after ->> 0)::integer and x."sequence" > (v_after ->> 1)::bigint) or (coalesce(x."residual_score", -1) = (v_after ->> 0)::integer and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."residual_score", -1) desc, x."sequence" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'matrixId', x."matrix_id", 'title', x."title", 'description', x."description", 'category', x."category", 'cause', x."cause", 'consequence', x."consequence", 'ownerId', x."owner_id", 'status', x."status", 'treatment', x."treatment", 'reviewIntervalMonths', x."review_interval_months", 'nextReviewOn', x."next_review_on", 'reviewedAt', x."reviewed_at", 'inherent', case when x."inherent_score" is null then null else jsonb_build_object('likelihood', x."inherent_likelihood", 'impact', x."inherent_impact", 'score', x."inherent_score", 'band', x."inherent_band") end, 'residual', case when x."residual_score" is null then null else jsonb_build_object('likelihood', x."residual_likelihood", 'impact', x."residual_impact", 'score', x."residual_score", 'band', x."residual_band") end, 'currentAssessmentId', x."current_assessment_id", 'closedAt', x."closed_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."risks" x
      where x."tenant_id" = list_risks.tenant
        and x."archived_at" is null
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" <> 'closed' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or x."category" = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (not (v_filters -> 'band' is not null and jsonb_typeof(v_filters -> 'band') <> 'null' and not (jsonb_typeof(v_filters -> 'band') = 'array' and jsonb_array_length(v_filters -> 'band') = 0)) or x."residual_band" = any((case when jsonb_typeof(v_filters -> 'band') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'band')) else array[v_filters ->> 'band'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or x."next_review_on" <= current_date)
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."cause" ilike v_search or x."consequence" ilike v_search)
        and (v_after is null or (x."sequence", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."sequence" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'matrixId', x."matrix_id", 'title', x."title", 'description', x."description", 'category', x."category", 'cause', x."cause", 'consequence', x."consequence", 'ownerId', x."owner_id", 'status', x."status", 'treatment', x."treatment", 'reviewIntervalMonths', x."review_interval_months", 'nextReviewOn', x."next_review_on", 'reviewedAt', x."reviewed_at", 'inherent', case when x."inherent_score" is null then null else jsonb_build_object('likelihood', x."inherent_likelihood", 'impact', x."inherent_impact", 'score', x."inherent_score", 'band', x."inherent_band") end, 'residual', case when x."residual_score" is null then null else jsonb_build_object('likelihood', x."residual_likelihood", 'impact', x."residual_impact", 'score', x."residual_score", 'band', x."residual_band") end, 'currentAssessmentId', x."current_assessment_id", 'closedAt', x."closed_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."risks" x
      where x."tenant_id" = list_risks.tenant
        and x."archived_at" is null
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" <> 'closed' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or x."category" = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (not (v_filters -> 'band' is not null and jsonb_typeof(v_filters -> 'band') <> 'null' and not (jsonb_typeof(v_filters -> 'band') = 'array' and jsonb_array_length(v_filters -> 'band') = 0)) or x."residual_band" = any((case when jsonb_typeof(v_filters -> 'band') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'band')) else array[v_filters ->> 'band'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or x."next_review_on" <= current_date)
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."cause" ilike v_search or x."consequence" ilike v_search)
        and (v_after is null or (x."sequence" <= (v_after ->> 0)::bigint and ((x."sequence" < (v_after ->> 0)::bigint) or (x."sequence" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'nextReviewOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'matrixId', x."matrix_id", 'title', x."title", 'description', x."description", 'category', x."category", 'cause', x."cause", 'consequence', x."consequence", 'ownerId', x."owner_id", 'status', x."status", 'treatment', x."treatment", 'reviewIntervalMonths', x."review_interval_months", 'nextReviewOn', x."next_review_on", 'reviewedAt', x."reviewed_at", 'inherent', case when x."inherent_score" is null then null else jsonb_build_object('likelihood', x."inherent_likelihood", 'impact', x."inherent_impact", 'score', x."inherent_score", 'band', x."inherent_band") end, 'residual', case when x."residual_score" is null then null else jsonb_build_object('likelihood', x."residual_likelihood", 'impact', x."residual_impact", 'score', x."residual_score", 'band', x."residual_band") end, 'currentAssessmentId', x."current_assessment_id", 'closedAt', x."closed_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."next_review_on", 'infinity'::date))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."risks" x
      where x."tenant_id" = list_risks.tenant
        and x."archived_at" is null
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" <> 'closed' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or x."category" = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (not (v_filters -> 'band' is not null and jsonb_typeof(v_filters -> 'band') <> 'null' and not (jsonb_typeof(v_filters -> 'band') = 'array' and jsonb_array_length(v_filters -> 'band') = 0)) or x."residual_band" = any((case when jsonb_typeof(v_filters -> 'band') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'band')) else array[v_filters ->> 'band'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or x."next_review_on" <= current_date)
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."cause" ilike v_search or x."consequence" ilike v_search)
        and (v_after is null or (coalesce(x."next_review_on", 'infinity'::date), x."sequence", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::bigint, (v_after ->> 2)::uuid))
      order by coalesce(x."next_review_on", 'infinity'::date) asc, x."sequence" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'nextReviewOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'matrixId', x."matrix_id", 'title', x."title", 'description', x."description", 'category', x."category", 'cause', x."cause", 'consequence', x."consequence", 'ownerId', x."owner_id", 'status', x."status", 'treatment', x."treatment", 'reviewIntervalMonths', x."review_interval_months", 'nextReviewOn', x."next_review_on", 'reviewedAt', x."reviewed_at", 'inherent', case when x."inherent_score" is null then null else jsonb_build_object('likelihood', x."inherent_likelihood", 'impact', x."inherent_impact", 'score', x."inherent_score", 'band', x."inherent_band") end, 'residual', case when x."residual_score" is null then null else jsonb_build_object('likelihood', x."residual_likelihood", 'impact', x."residual_impact", 'score', x."residual_score", 'band', x."residual_band") end, 'currentAssessmentId', x."current_assessment_id", 'closedAt', x."closed_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."next_review_on", 'infinity'::date))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."risks" x
      where x."tenant_id" = list_risks.tenant
        and x."archived_at" is null
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" <> 'closed' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or x."category" = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (not (v_filters -> 'band' is not null and jsonb_typeof(v_filters -> 'band') <> 'null' and not (jsonb_typeof(v_filters -> 'band') = 'array' and jsonb_array_length(v_filters -> 'band') = 0)) or x."residual_band" = any((case when jsonb_typeof(v_filters -> 'band') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'band')) else array[v_filters ->> 'band'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or x."next_review_on" <= current_date)
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."cause" ilike v_search or x."consequence" ilike v_search)
        and (v_after is null or (coalesce(x."next_review_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."next_review_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."next_review_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" > (v_after ->> 1)::bigint) or (coalesce(x."next_review_on", 'infinity'::date) = (v_after ->> 0)::date and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."next_review_on", 'infinity'::date) desc, x."sequence" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."risks" x
      where x."tenant_id" = list_risks.tenant
        and x."archived_at" is null
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" <> 'closed' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or x."category" = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (not (v_filters -> 'band' is not null and jsonb_typeof(v_filters -> 'band') <> 'null' and not (jsonb_typeof(v_filters -> 'band') = 'array' and jsonb_array_length(v_filters -> 'band') = 0)) or x."residual_band" = any((case when jsonb_typeof(v_filters -> 'band') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'band')) else array[v_filters ->> 'band'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id" = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::uuid[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or x."next_review_on" <= current_date)
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."cause" ilike v_search or x."consequence" ilike v_search)
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
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_usage_rights (
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
  v_filters jsonb := coalesce(list_usage_rights.filters, '{}'::jsonb);
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
  v_expiring integer := nullif(coalesce(v_filters #>> '{expiringWithinDays,0}', v_filters ->> 'expiringWithinDays'), '')::integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_usage_rights.tenant is not null and coalesce(better_supabase.can('tenant', list_usage_rights.tenant, 'dam.read'), false))) then
    raise exception 'not allowed to read usage rights' using errcode = '42501', hint = 'DAM_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'DAM_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'DAM_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end)::text end) as v
      from "better_supabase"."dam_usage_rights" x
      where x."tenant_id" = list_usage_rights.tenant
        and (not (v_filters -> 'nodeId' is not null and jsonb_typeof(v_filters -> 'nodeId') <> 'null' and not (jsonb_typeof(v_filters -> 'nodeId') = 'array' and jsonb_array_length(v_filters -> 'nodeId') = 0)) or x."node_id" = any((case when jsonb_typeof(v_filters -> 'nodeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'nodeId')) else array[v_filters ->> 'nodeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end) = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_expiring is null or (x."revoked_at" is null and x."expires_on" is not null and x."expires_on" between current_date and current_date + v_expiring))
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
      select 1 from "better_supabase"."dam_usage_rights" x
      where x."tenant_id" = list_usage_rights.tenant
        and (not (v_filters -> 'nodeId' is not null and jsonb_typeof(v_filters -> 'nodeId') <> 'null' and not (jsonb_typeof(v_filters -> 'nodeId') = 'array' and jsonb_array_length(v_filters -> 'nodeId') = 0)) or x."node_id" = any((case when jsonb_typeof(v_filters -> 'nodeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'nodeId')) else array[v_filters ->> 'nodeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end) = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_expiring is null or (x."revoked_at" is null and x."expires_on" is not null and x."expires_on" between current_date and current_date + v_expiring))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('expiresOn', 'startsOn') then
    raise exception 'sort is one of expiresOn, startsOn' using errcode = '22023', hint = 'DAM_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'DAM_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'nodeId', x."node_id", 'licensee', x."licensee", 'territory', x."territory", 'channel', x."channel", 'startsOn', x."starts_on", 'expiresOn', x."expires_on", 'status', case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end, 'note', x."note", 'revokedAt', x."revoked_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((coalesce(x."expires_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."dam_usage_rights" x
      where x."tenant_id" = list_usage_rights.tenant
        and (not (v_filters -> 'nodeId' is not null and jsonb_typeof(v_filters -> 'nodeId') <> 'null' and not (jsonb_typeof(v_filters -> 'nodeId') = 'array' and jsonb_array_length(v_filters -> 'nodeId') = 0)) or x."node_id" = any((case when jsonb_typeof(v_filters -> 'nodeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'nodeId')) else array[v_filters ->> 'nodeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end) = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_expiring is null or (x."revoked_at" is null and x."expires_on" is not null and x."expires_on" between current_date and current_date + v_expiring))
        and (v_after is null or (coalesce(x."expires_on", 'infinity'::date), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."expires_on", 'infinity'::date) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'nodeId', x."node_id", 'licensee', x."licensee", 'territory', x."territory", 'channel', x."channel", 'startsOn', x."starts_on", 'expiresOn', x."expires_on", 'status', case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end, 'note', x."note", 'revokedAt', x."revoked_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((coalesce(x."expires_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."dam_usage_rights" x
      where x."tenant_id" = list_usage_rights.tenant
        and (not (v_filters -> 'nodeId' is not null and jsonb_typeof(v_filters -> 'nodeId') <> 'null' and not (jsonb_typeof(v_filters -> 'nodeId') = 'array' and jsonb_array_length(v_filters -> 'nodeId') = 0)) or x."node_id" = any((case when jsonb_typeof(v_filters -> 'nodeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'nodeId')) else array[v_filters ->> 'nodeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end) = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_expiring is null or (x."revoked_at" is null and x."expires_on" is not null and x."expires_on" between current_date and current_date + v_expiring))
        and (v_after is null or (coalesce(x."expires_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."expires_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."expires_on", 'infinity'::date) = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."expires_on", 'infinity'::date) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'expiresOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'nodeId', x."node_id", 'licensee', x."licensee", 'territory', x."territory", 'channel', x."channel", 'startsOn', x."starts_on", 'expiresOn', x."expires_on", 'status', case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end, 'note', x."note", 'revokedAt', x."revoked_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((coalesce(x."expires_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."dam_usage_rights" x
      where x."tenant_id" = list_usage_rights.tenant
        and (not (v_filters -> 'nodeId' is not null and jsonb_typeof(v_filters -> 'nodeId') <> 'null' and not (jsonb_typeof(v_filters -> 'nodeId') = 'array' and jsonb_array_length(v_filters -> 'nodeId') = 0)) or x."node_id" = any((case when jsonb_typeof(v_filters -> 'nodeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'nodeId')) else array[v_filters ->> 'nodeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end) = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_expiring is null or (x."revoked_at" is null and x."expires_on" is not null and x."expires_on" between current_date and current_date + v_expiring))
        and (v_after is null or (coalesce(x."expires_on", 'infinity'::date), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."expires_on", 'infinity'::date) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'expiresOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'nodeId', x."node_id", 'licensee', x."licensee", 'territory', x."territory", 'channel', x."channel", 'startsOn', x."starts_on", 'expiresOn', x."expires_on", 'status', case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end, 'note', x."note", 'revokedAt', x."revoked_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((coalesce(x."expires_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."dam_usage_rights" x
      where x."tenant_id" = list_usage_rights.tenant
        and (not (v_filters -> 'nodeId' is not null and jsonb_typeof(v_filters -> 'nodeId') <> 'null' and not (jsonb_typeof(v_filters -> 'nodeId') = 'array' and jsonb_array_length(v_filters -> 'nodeId') = 0)) or x."node_id" = any((case when jsonb_typeof(v_filters -> 'nodeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'nodeId')) else array[v_filters ->> 'nodeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end) = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_expiring is null or (x."revoked_at" is null and x."expires_on" is not null and x."expires_on" between current_date and current_date + v_expiring))
        and (v_after is null or (coalesce(x."expires_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."expires_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."expires_on", 'infinity'::date) = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."expires_on", 'infinity'::date) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'nodeId', x."node_id", 'licensee', x."licensee", 'territory', x."territory", 'channel', x."channel", 'startsOn', x."starts_on", 'expiresOn', x."expires_on", 'status', case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end, 'note', x."note", 'revokedAt', x."revoked_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((coalesce(x."starts_on", '-infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."dam_usage_rights" x
      where x."tenant_id" = list_usage_rights.tenant
        and (not (v_filters -> 'nodeId' is not null and jsonb_typeof(v_filters -> 'nodeId') <> 'null' and not (jsonb_typeof(v_filters -> 'nodeId') = 'array' and jsonb_array_length(v_filters -> 'nodeId') = 0)) or x."node_id" = any((case when jsonb_typeof(v_filters -> 'nodeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'nodeId')) else array[v_filters ->> 'nodeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end) = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_expiring is null or (x."revoked_at" is null and x."expires_on" is not null and x."expires_on" between current_date and current_date + v_expiring))
        and (v_after is null or (coalesce(x."starts_on", '-infinity'::date), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."starts_on", '-infinity'::date) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'nodeId', x."node_id", 'licensee', x."licensee", 'territory', x."territory", 'channel', x."channel", 'startsOn', x."starts_on", 'expiresOn', x."expires_on", 'status', case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end, 'note', x."note", 'revokedAt', x."revoked_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((coalesce(x."starts_on", '-infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."dam_usage_rights" x
      where x."tenant_id" = list_usage_rights.tenant
        and (not (v_filters -> 'nodeId' is not null and jsonb_typeof(v_filters -> 'nodeId') <> 'null' and not (jsonb_typeof(v_filters -> 'nodeId') = 'array' and jsonb_array_length(v_filters -> 'nodeId') = 0)) or x."node_id" = any((case when jsonb_typeof(v_filters -> 'nodeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'nodeId')) else array[v_filters ->> 'nodeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end) = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_expiring is null or (x."revoked_at" is null and x."expires_on" is not null and x."expires_on" between current_date and current_date + v_expiring))
        and (v_after is null or (coalesce(x."starts_on", '-infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."starts_on", '-infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."starts_on", '-infinity'::date) = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."starts_on", '-infinity'::date) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."dam_usage_rights" x
      where x."tenant_id" = list_usage_rights.tenant
        and (not (v_filters -> 'nodeId' is not null and jsonb_typeof(v_filters -> 'nodeId') <> 'null' and not (jsonb_typeof(v_filters -> 'nodeId') = 'array' and jsonb_array_length(v_filters -> 'nodeId') = 0)) or x."node_id" = any((case when jsonb_typeof(v_filters -> 'nodeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'nodeId')) else array[v_filters ->> 'nodeId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end) = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_expiring is null or (x."revoked_at" is null and x."expires_on" is not null and x."expires_on" between current_date and current_date + v_expiring))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."get_calibration"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_calibration"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_maintenance_plan"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_maintenance_plan"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_usage_right"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_usage_right"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_calibration"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_calibration"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_maintenance_plan"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_maintenance_plan"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_usage_right"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_usage_right"(uuid) TO "authenticated", "service_role";
