SET local check_function_bodies = off;

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
  v_cycle text := nullif(v_filters ->> 'cycleId', '');
  v_status text := nullif(v_filters ->> 'status', '');
  v_subject text := nullif(v_filters ->> 'subjectUserId', '');
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_appraisals.tenant is not null and coalesce(better_supabase.can('tenant', list_appraisals.tenant, 'appraisals.read'), false)));
begin
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
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
        and (v_cycle is null or x."cycle_id" = v_cycle::uuid)
        and (v_status is null or x."status" = v_status)
        and (v_subject is null or x."appraisee_id" = v_subject::uuid)
        and ((v_all and (v_filters ->> 'mine') is distinct from 'true') or (x."appraisee_id" = auth.uid()
    or exists (select 1 from "better_supabase"."appraisal_reviews" z where z."appraisal_id" = x."id" and z."reviewer_id" = auth.uid())))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."appraisals" x
      where x."tenant_id" = list_appraisals.tenant
        and (v_cycle is null or x."cycle_id" = v_cycle::uuid)
        and (v_status is null or x."status" = v_status)
        and (v_subject is null or x."appraisee_id" = v_subject::uuid)
        and ((v_all and (v_filters ->> 'mine') is distinct from 'true') or (x."appraisee_id" = auth.uid()
    or exists (select 1 from "better_supabase"."appraisal_reviews" z where z."appraisal_id" = x."id" and z."reviewer_id" = auth.uid())))
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
  v_wave text := nullif(v_filters ->> 'waveId', '');
  v_status text := nullif(v_filters ->> 'status', '');
  v_doc_type text := nullif(v_filters ->> 'documentType', '');
  v_doc_id text := nullif(v_filters ->> 'documentId', '');
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_pick_lists.tenant is not null and coalesce(better_supabase.can('tenant', list_pick_lists.tenant, 'warehouse.read'), false)));
begin
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'WAREHOUSE_INVALID';
  end if;
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
        and (v_wave is null or x."wave_id" = v_wave::uuid)
        and (v_status is null or x."status" = v_status)
        and (v_doc_type is null or x."document_type" = v_doc_type)
        and (v_doc_id is null or x."document_id" = v_doc_id)
        and ((v_all and (v_filters ->> 'mine') is distinct from 'true') or coalesce(x."assignee_id" = auth.uid(), false))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."pick_lists" x
      where x."tenant_id" = list_pick_lists.tenant
        and (v_wave is null or x."wave_id" = v_wave::uuid)
        and (v_status is null or x."status" = v_status)
        and (v_doc_type is null or x."document_type" = v_doc_type)
        and (v_doc_id is null or x."document_id" = v_doc_id)
        and ((v_all and (v_filters ->> 'mine') is distinct from 'true') or coalesce(x."assignee_id" = auth.uid(), false))
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
  v_node text := nullif(v_filters ->> 'nodeId', '');
  v_status text := nullif(v_filters ->> 'status', '');
  v_expiring integer := (v_filters ->> 'expiringWithinDays')::integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_usage_rights.tenant is not null and coalesce(better_supabase.can('tenant', list_usage_rights.tenant, 'dam.read'), false))) then
    raise exception 'not allowed to read usage rights' using errcode = '42501', hint = 'DAM_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'DAM_INVALID';
  end if;
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
        and (v_node is null or x."node_id" = v_node::uuid)
        and (v_status is null or case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end = v_status)
        and (v_expiring is null or (x."revoked_at" is null and x."expires_on" is not null and x."expires_on" between current_date and current_date + v_expiring))
        and (v_after is null or (coalesce(x."expires_on", 'infinity'::date), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."expires_on", 'infinity'::date) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."dam_usage_rights" x
      where x."tenant_id" = list_usage_rights.tenant
        and (v_node is null or x."node_id" = v_node::uuid)
        and (v_status is null or case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end = v_status)
        and (v_expiring is null or (x."revoked_at" is null and x."expires_on" is not null and x."expires_on" between current_date and current_date + v_expiring))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE INDEX appraisals_list_idx ON better_supabase.appraisals USING btree (tenant_id, created_at DESC, id);

CREATE INDEX dam_usage_rights_list_idx ON better_supabase.dam_usage_rights USING btree (tenant_id, COALESCE(expires_on, 'infinity'::date), id);

CREATE INDEX maintenance_plans_list_idx ON better_supabase.maintenance_plans USING btree (tenant_id, COALESCE(next_due_at, 'infinity'::timestamp WITH time zone), id);

CREATE INDEX pick_lists_list_idx ON better_supabase.pick_lists USING btree (tenant_id, created_at DESC, id);
