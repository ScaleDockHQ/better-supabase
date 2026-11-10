SET local check_function_bodies = off;

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
  v_status text := nullif(v_filters ->> 'status', '');
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_rfqs.tenant is not null and coalesce(better_supabase.can('tenant', list_rfqs.tenant, 'rfqs.read'), false))) then
    raise exception 'not allowed to read requests for quotation' using errcode = '42501', hint = 'RFQ_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
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
        and (v_status is null or x."status" = v_status)
        and (v_after is null or (x."sequence" <= (v_after ->> 0)::bigint and ((x."sequence" < (v_after ->> 0)::bigint) or (x."sequence" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."rfqs" x
      where x."tenant_id" = list_rfqs.tenant
        and (v_status is null or x."status" = v_status)
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
  v_status text := nullif(v_filters ->> 'status', '');
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_samples.tenant is not null and coalesce(better_supabase.can('tenant', list_samples.tenant, 'lims.read'), false))) then
    raise exception 'not allowed to read samples' using errcode = '42501', hint = 'LIMS_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'LIMS_INVALID';
  end if;
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
        and (v_status is null or x."status" = v_status)
        and (v_after is null or (x."sequence" <= (v_after ->> 0)::bigint and ((x."sequence" < (v_after ->> 0)::bigint) or (x."sequence" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."lims_samples" x
      where x."tenant_id" = list_samples.tenant
        and (v_status is null or x."status" = v_status)
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
  v_till text := nullif(v_filters ->> 'tillId', '');
  v_status text := nullif(v_filters ->> 'status', '');
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_till_sessions.tenant is not null and coalesce(better_supabase.can('tenant', list_till_sessions.tenant, 'tills.read'), false))) then
    raise exception 'not allowed to read till sessions' using errcode = '42501', hint = 'TILL_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
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
        and (v_till is null or x."till_id"::text = v_till)
        and (v_status is null or x."status" = v_status)
        and (v_after is null or (x."opened_at" <= (v_after ->> 0)::timestamptz and ((x."opened_at" < (v_after ->> 0)::timestamptz) or (x."opened_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."opened_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (v_till is null or x."till_id"::text = v_till)
        and (v_status is null or x."status" = v_status)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE INDEX lims_samples_list_idx ON better_supabase.lims_samples USING btree (tenant_id, SEQUENCE DESC, id);

CREATE INDEX maintenance_calibrations_list_idx ON better_supabase.maintenance_calibrations USING btree (tenant_id, performed_at DESC, id);

CREATE INDEX rfqs_list_idx ON better_supabase.rfqs USING btree (tenant_id, SEQUENCE DESC, id);

CREATE INDEX till_sessions_list_idx ON better_supabase.till_sessions USING btree (tenant_id, opened_at DESC, id);
