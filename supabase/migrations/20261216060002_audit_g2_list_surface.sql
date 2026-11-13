SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.get_warranty_claim (
  claim_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_warranty_claim"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_warranty_claim (
  claim_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."warranty_claims";
begin
  select * into v_row from "better_supabase"."warranty_claims" x where x."id" = get_warranty_claim.claim_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'warranty.read'), false))) then
    raise exception 'no such warranty claim' using errcode = 'P0002', hint = 'WARRANTY_NOT_FOUND';
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'organizationId', v_row."tenant_id",
    'title', v_row."title",
    'assetId', v_row."asset_id",
    'supplierId', v_row."supplier_id",
    'manufacturer', v_row."manufacturer",
    'amount', v_row."amount"::text,
    'currency', v_row."currency",
    'status', v_row."status",
    'decision', v_row."decision",
    'decidedAt', v_row."decided_at",
    'decidedBy', v_row."decided_by");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_inspections (
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
  v_filters jsonb := coalesce(list_inspections.filters, '{}'::jsonb);
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
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_inspections.tenant is not null and coalesce(better_supabase.can('tenant', list_inspections.tenant, 'inspections.read'), false)));
begin
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if not v_all and auth.uid() is null then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'kind') then
      raise exception 'facet is one of status, kind' using errcode = '22023', hint = 'INSPECTION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'kind' then (x."kind")::text end) as v
      from "better_supabase"."inspections" x
      where x."tenant_id" = list_inspections.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."inspection_members" y where y."inspection_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'programId' is not null and jsonb_typeof(v_filters -> 'programId') <> 'null' and not (jsonb_typeof(v_filters -> 'programId') = 'array' and jsonb_array_length(v_filters -> 'programId') = 0)) or x."program_id" = any((case when jsonb_typeof(v_filters -> 'programId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'programId')) else array[v_filters ->> 'programId'] end)::uuid[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'leadId' is not null and jsonb_typeof(v_filters -> 'leadId') <> 'null' and not (jsonb_typeof(v_filters -> 'leadId') = 'array' and jsonb_array_length(v_filters -> 'leadId') = 0)) or x."lead_id" = any((case when jsonb_typeof(v_filters -> 'leadId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'leadId')) else array[v_filters ->> 'leadId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."planned_start" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::date)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."planned_start" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::date)
        and (not (v_filters -> 'auditeeType' is not null and jsonb_typeof(v_filters -> 'auditeeType') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeType') = 'array' and jsonb_array_length(v_filters -> 'auditeeType') = 0)) or x."auditee_type" = any((case when jsonb_typeof(v_filters -> 'auditeeType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeType')) else array[v_filters ->> 'auditeeType'] end)::text[]))
        and (not (v_filters -> 'auditeeId' is not null and jsonb_typeof(v_filters -> 'auditeeId') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeId') = 'array' and jsonb_array_length(v_filters -> 'auditeeId') = 0)) or x."auditee_id" = any((case when jsonb_typeof(v_filters -> 'auditeeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeId')) else array[v_filters ->> 'auditeeId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."scope" ilike v_search or x."summary" ilike v_search)
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
      select 1 from "better_supabase"."inspections" x
      where x."tenant_id" = list_inspections.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."inspection_members" y where y."inspection_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'programId' is not null and jsonb_typeof(v_filters -> 'programId') <> 'null' and not (jsonb_typeof(v_filters -> 'programId') = 'array' and jsonb_array_length(v_filters -> 'programId') = 0)) or x."program_id" = any((case when jsonb_typeof(v_filters -> 'programId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'programId')) else array[v_filters ->> 'programId'] end)::uuid[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'leadId' is not null and jsonb_typeof(v_filters -> 'leadId') <> 'null' and not (jsonb_typeof(v_filters -> 'leadId') = 'array' and jsonb_array_length(v_filters -> 'leadId') = 0)) or x."lead_id" = any((case when jsonb_typeof(v_filters -> 'leadId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'leadId')) else array[v_filters ->> 'leadId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."planned_start" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::date)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."planned_start" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::date)
        and (not (v_filters -> 'auditeeType' is not null and jsonb_typeof(v_filters -> 'auditeeType') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeType') = 'array' and jsonb_array_length(v_filters -> 'auditeeType') = 0)) or x."auditee_type" = any((case when jsonb_typeof(v_filters -> 'auditeeType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeType')) else array[v_filters ->> 'auditeeType'] end)::text[]))
        and (not (v_filters -> 'auditeeId' is not null and jsonb_typeof(v_filters -> 'auditeeId') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeId') = 'array' and jsonb_array_length(v_filters -> 'auditeeId') = 0)) or x."auditee_id" = any((case when jsonb_typeof(v_filters -> 'auditeeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeId')) else array[v_filters ->> 'auditeeId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."scope" ilike v_search or x."summary" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('plannedStart', 'number') then
    raise exception 'sort is one of plannedStart, number' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditee', case when x."auditee_type" is null then null else jsonb_build_object('type', x."auditee_type", 'id', x."auditee_id") end, 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'checklistFormId', x."checklist_form_id", 'checklistSubmissionId', x."checklist_submission_id", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."planned_start", '-infinity'::date))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inspections" x
      where x."tenant_id" = list_inspections.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."inspection_members" y where y."inspection_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'programId' is not null and jsonb_typeof(v_filters -> 'programId') <> 'null' and not (jsonb_typeof(v_filters -> 'programId') = 'array' and jsonb_array_length(v_filters -> 'programId') = 0)) or x."program_id" = any((case when jsonb_typeof(v_filters -> 'programId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'programId')) else array[v_filters ->> 'programId'] end)::uuid[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'leadId' is not null and jsonb_typeof(v_filters -> 'leadId') <> 'null' and not (jsonb_typeof(v_filters -> 'leadId') = 'array' and jsonb_array_length(v_filters -> 'leadId') = 0)) or x."lead_id" = any((case when jsonb_typeof(v_filters -> 'leadId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'leadId')) else array[v_filters ->> 'leadId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."planned_start" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::date)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."planned_start" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::date)
        and (not (v_filters -> 'auditeeType' is not null and jsonb_typeof(v_filters -> 'auditeeType') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeType') = 'array' and jsonb_array_length(v_filters -> 'auditeeType') = 0)) or x."auditee_type" = any((case when jsonb_typeof(v_filters -> 'auditeeType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeType')) else array[v_filters ->> 'auditeeType'] end)::text[]))
        and (not (v_filters -> 'auditeeId' is not null and jsonb_typeof(v_filters -> 'auditeeId') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeId') = 'array' and jsonb_array_length(v_filters -> 'auditeeId') = 0)) or x."auditee_id" = any((case when jsonb_typeof(v_filters -> 'auditeeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeId')) else array[v_filters ->> 'auditeeId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."scope" ilike v_search or x."summary" ilike v_search)
        and (v_after is null or (coalesce(x."planned_start", '-infinity'::date) >= (v_after ->> 0)::date and ((coalesce(x."planned_start", '-infinity'::date) > (v_after ->> 0)::date) or (coalesce(x."planned_start", '-infinity'::date) = (v_after ->> 0)::date and x."sequence" < (v_after ->> 1)::bigint) or (coalesce(x."planned_start", '-infinity'::date) = (v_after ->> 0)::date and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."planned_start", '-infinity'::date) asc, x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditee', case when x."auditee_type" is null then null else jsonb_build_object('type', x."auditee_type", 'id', x."auditee_id") end, 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'checklistFormId', x."checklist_form_id", 'checklistSubmissionId', x."checklist_submission_id", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."planned_start", '-infinity'::date))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inspections" x
      where x."tenant_id" = list_inspections.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."inspection_members" y where y."inspection_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'programId' is not null and jsonb_typeof(v_filters -> 'programId') <> 'null' and not (jsonb_typeof(v_filters -> 'programId') = 'array' and jsonb_array_length(v_filters -> 'programId') = 0)) or x."program_id" = any((case when jsonb_typeof(v_filters -> 'programId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'programId')) else array[v_filters ->> 'programId'] end)::uuid[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'leadId' is not null and jsonb_typeof(v_filters -> 'leadId') <> 'null' and not (jsonb_typeof(v_filters -> 'leadId') = 'array' and jsonb_array_length(v_filters -> 'leadId') = 0)) or x."lead_id" = any((case when jsonb_typeof(v_filters -> 'leadId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'leadId')) else array[v_filters ->> 'leadId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."planned_start" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::date)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."planned_start" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::date)
        and (not (v_filters -> 'auditeeType' is not null and jsonb_typeof(v_filters -> 'auditeeType') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeType') = 'array' and jsonb_array_length(v_filters -> 'auditeeType') = 0)) or x."auditee_type" = any((case when jsonb_typeof(v_filters -> 'auditeeType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeType')) else array[v_filters ->> 'auditeeType'] end)::text[]))
        and (not (v_filters -> 'auditeeId' is not null and jsonb_typeof(v_filters -> 'auditeeId') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeId') = 'array' and jsonb_array_length(v_filters -> 'auditeeId') = 0)) or x."auditee_id" = any((case when jsonb_typeof(v_filters -> 'auditeeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeId')) else array[v_filters ->> 'auditeeId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."scope" ilike v_search or x."summary" ilike v_search)
        and (v_after is null or (coalesce(x."planned_start", '-infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."planned_start", '-infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."planned_start", '-infinity'::date) = (v_after ->> 0)::date and x."sequence" < (v_after ->> 1)::bigint) or (coalesce(x."planned_start", '-infinity'::date) = (v_after ->> 0)::date and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."planned_start", '-infinity'::date) desc, x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'plannedStart' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditee', case when x."auditee_type" is null then null else jsonb_build_object('type', x."auditee_type", 'id', x."auditee_id") end, 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'checklistFormId', x."checklist_form_id", 'checklistSubmissionId', x."checklist_submission_id", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."planned_start", '-infinity'::date))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inspections" x
      where x."tenant_id" = list_inspections.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."inspection_members" y where y."inspection_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'programId' is not null and jsonb_typeof(v_filters -> 'programId') <> 'null' and not (jsonb_typeof(v_filters -> 'programId') = 'array' and jsonb_array_length(v_filters -> 'programId') = 0)) or x."program_id" = any((case when jsonb_typeof(v_filters -> 'programId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'programId')) else array[v_filters ->> 'programId'] end)::uuid[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'leadId' is not null and jsonb_typeof(v_filters -> 'leadId') <> 'null' and not (jsonb_typeof(v_filters -> 'leadId') = 'array' and jsonb_array_length(v_filters -> 'leadId') = 0)) or x."lead_id" = any((case when jsonb_typeof(v_filters -> 'leadId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'leadId')) else array[v_filters ->> 'leadId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."planned_start" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::date)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."planned_start" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::date)
        and (not (v_filters -> 'auditeeType' is not null and jsonb_typeof(v_filters -> 'auditeeType') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeType') = 'array' and jsonb_array_length(v_filters -> 'auditeeType') = 0)) or x."auditee_type" = any((case when jsonb_typeof(v_filters -> 'auditeeType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeType')) else array[v_filters ->> 'auditeeType'] end)::text[]))
        and (not (v_filters -> 'auditeeId' is not null and jsonb_typeof(v_filters -> 'auditeeId') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeId') = 'array' and jsonb_array_length(v_filters -> 'auditeeId') = 0)) or x."auditee_id" = any((case when jsonb_typeof(v_filters -> 'auditeeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeId')) else array[v_filters ->> 'auditeeId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."scope" ilike v_search or x."summary" ilike v_search)
        and (v_after is null or (coalesce(x."planned_start", '-infinity'::date) >= (v_after ->> 0)::date and ((coalesce(x."planned_start", '-infinity'::date) > (v_after ->> 0)::date) or (coalesce(x."planned_start", '-infinity'::date) = (v_after ->> 0)::date and x."sequence" < (v_after ->> 1)::bigint) or (coalesce(x."planned_start", '-infinity'::date) = (v_after ->> 0)::date and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."planned_start", '-infinity'::date) asc, x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'plannedStart' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditee', case when x."auditee_type" is null then null else jsonb_build_object('type', x."auditee_type", 'id', x."auditee_id") end, 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'checklistFormId', x."checklist_form_id", 'checklistSubmissionId', x."checklist_submission_id", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."planned_start", '-infinity'::date))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inspections" x
      where x."tenant_id" = list_inspections.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."inspection_members" y where y."inspection_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'programId' is not null and jsonb_typeof(v_filters -> 'programId') <> 'null' and not (jsonb_typeof(v_filters -> 'programId') = 'array' and jsonb_array_length(v_filters -> 'programId') = 0)) or x."program_id" = any((case when jsonb_typeof(v_filters -> 'programId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'programId')) else array[v_filters ->> 'programId'] end)::uuid[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'leadId' is not null and jsonb_typeof(v_filters -> 'leadId') <> 'null' and not (jsonb_typeof(v_filters -> 'leadId') = 'array' and jsonb_array_length(v_filters -> 'leadId') = 0)) or x."lead_id" = any((case when jsonb_typeof(v_filters -> 'leadId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'leadId')) else array[v_filters ->> 'leadId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."planned_start" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::date)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."planned_start" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::date)
        and (not (v_filters -> 'auditeeType' is not null and jsonb_typeof(v_filters -> 'auditeeType') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeType') = 'array' and jsonb_array_length(v_filters -> 'auditeeType') = 0)) or x."auditee_type" = any((case when jsonb_typeof(v_filters -> 'auditeeType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeType')) else array[v_filters ->> 'auditeeType'] end)::text[]))
        and (not (v_filters -> 'auditeeId' is not null and jsonb_typeof(v_filters -> 'auditeeId') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeId') = 'array' and jsonb_array_length(v_filters -> 'auditeeId') = 0)) or x."auditee_id" = any((case when jsonb_typeof(v_filters -> 'auditeeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeId')) else array[v_filters ->> 'auditeeId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."scope" ilike v_search or x."summary" ilike v_search)
        and (v_after is null or (coalesce(x."planned_start", '-infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."planned_start", '-infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."planned_start", '-infinity'::date) = (v_after ->> 0)::date and x."sequence" < (v_after ->> 1)::bigint) or (coalesce(x."planned_start", '-infinity'::date) = (v_after ->> 0)::date and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."planned_start", '-infinity'::date) desc, x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditee', case when x."auditee_type" is null then null else jsonb_build_object('type', x."auditee_type", 'id', x."auditee_id") end, 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'checklistFormId', x."checklist_form_id", 'checklistSubmissionId', x."checklist_submission_id", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inspections" x
      where x."tenant_id" = list_inspections.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."inspection_members" y where y."inspection_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'programId' is not null and jsonb_typeof(v_filters -> 'programId') <> 'null' and not (jsonb_typeof(v_filters -> 'programId') = 'array' and jsonb_array_length(v_filters -> 'programId') = 0)) or x."program_id" = any((case when jsonb_typeof(v_filters -> 'programId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'programId')) else array[v_filters ->> 'programId'] end)::uuid[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'leadId' is not null and jsonb_typeof(v_filters -> 'leadId') <> 'null' and not (jsonb_typeof(v_filters -> 'leadId') = 'array' and jsonb_array_length(v_filters -> 'leadId') = 0)) or x."lead_id" = any((case when jsonb_typeof(v_filters -> 'leadId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'leadId')) else array[v_filters ->> 'leadId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."planned_start" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::date)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."planned_start" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::date)
        and (not (v_filters -> 'auditeeType' is not null and jsonb_typeof(v_filters -> 'auditeeType') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeType') = 'array' and jsonb_array_length(v_filters -> 'auditeeType') = 0)) or x."auditee_type" = any((case when jsonb_typeof(v_filters -> 'auditeeType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeType')) else array[v_filters ->> 'auditeeType'] end)::text[]))
        and (not (v_filters -> 'auditeeId' is not null and jsonb_typeof(v_filters -> 'auditeeId') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeId') = 'array' and jsonb_array_length(v_filters -> 'auditeeId') = 0)) or x."auditee_id" = any((case when jsonb_typeof(v_filters -> 'auditeeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeId')) else array[v_filters ->> 'auditeeId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."scope" ilike v_search or x."summary" ilike v_search)
        and (v_after is null or (x."sequence", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."sequence" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditee', case when x."auditee_type" is null then null else jsonb_build_object('type', x."auditee_type", 'id', x."auditee_id") end, 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'checklistFormId', x."checklist_form_id", 'checklistSubmissionId', x."checklist_submission_id", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inspections" x
      where x."tenant_id" = list_inspections.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."inspection_members" y where y."inspection_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'programId' is not null and jsonb_typeof(v_filters -> 'programId') <> 'null' and not (jsonb_typeof(v_filters -> 'programId') = 'array' and jsonb_array_length(v_filters -> 'programId') = 0)) or x."program_id" = any((case when jsonb_typeof(v_filters -> 'programId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'programId')) else array[v_filters ->> 'programId'] end)::uuid[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'leadId' is not null and jsonb_typeof(v_filters -> 'leadId') <> 'null' and not (jsonb_typeof(v_filters -> 'leadId') = 'array' and jsonb_array_length(v_filters -> 'leadId') = 0)) or x."lead_id" = any((case when jsonb_typeof(v_filters -> 'leadId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'leadId')) else array[v_filters ->> 'leadId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."planned_start" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::date)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."planned_start" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::date)
        and (not (v_filters -> 'auditeeType' is not null and jsonb_typeof(v_filters -> 'auditeeType') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeType') = 'array' and jsonb_array_length(v_filters -> 'auditeeType') = 0)) or x."auditee_type" = any((case when jsonb_typeof(v_filters -> 'auditeeType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeType')) else array[v_filters ->> 'auditeeType'] end)::text[]))
        and (not (v_filters -> 'auditeeId' is not null and jsonb_typeof(v_filters -> 'auditeeId') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeId') = 'array' and jsonb_array_length(v_filters -> 'auditeeId') = 0)) or x."auditee_id" = any((case when jsonb_typeof(v_filters -> 'auditeeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeId')) else array[v_filters ->> 'auditeeId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."scope" ilike v_search or x."summary" ilike v_search)
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
      select 1 from "better_supabase"."inspections" x
      where x."tenant_id" = list_inspections.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."inspection_members" y where y."inspection_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'programId' is not null and jsonb_typeof(v_filters -> 'programId') <> 'null' and not (jsonb_typeof(v_filters -> 'programId') = 'array' and jsonb_array_length(v_filters -> 'programId') = 0)) or x."program_id" = any((case when jsonb_typeof(v_filters -> 'programId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'programId')) else array[v_filters ->> 'programId'] end)::uuid[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'leadId' is not null and jsonb_typeof(v_filters -> 'leadId') <> 'null' and not (jsonb_typeof(v_filters -> 'leadId') = 'array' and jsonb_array_length(v_filters -> 'leadId') = 0)) or x."lead_id" = any((case when jsonb_typeof(v_filters -> 'leadId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'leadId')) else array[v_filters ->> 'leadId'] end)::uuid[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."planned_start" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::date)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."planned_start" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::date)
        and (not (v_filters -> 'auditeeType' is not null and jsonb_typeof(v_filters -> 'auditeeType') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeType') = 'array' and jsonb_array_length(v_filters -> 'auditeeType') = 0)) or x."auditee_type" = any((case when jsonb_typeof(v_filters -> 'auditeeType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeType')) else array[v_filters ->> 'auditeeType'] end)::text[]))
        and (not (v_filters -> 'auditeeId' is not null and jsonb_typeof(v_filters -> 'auditeeId') <> 'null' and not (jsonb_typeof(v_filters -> 'auditeeId') = 'array' and jsonb_array_length(v_filters -> 'auditeeId') = 0)) or x."auditee_id" = any((case when jsonb_typeof(v_filters -> 'auditeeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'auditeeId')) else array[v_filters ->> 'auditeeId'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."scope" ilike v_search or x."summary" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_meetings (
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
  v_filters jsonb := coalesce(list_meetings.filters, '{}'::jsonb);
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
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_meetings.tenant is not null and coalesce(better_supabase.can('tenant', list_meetings.tenant, 'meetings.read'), false)));
begin
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if not v_all and auth.uid() is null then
    raise exception 'not allowed to read meetings' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind', 'status') then
      raise exception 'facet is one of kind, status' using errcode = '22023', hint = 'MEETING_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind")::text when 'status' then (x."status")::text end) as v
      from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
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
      select 1 from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsAt', 'title') then
    raise exception 'sort is one of startsAt, title' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'title', x."title", 'location', x."location", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'status', x."status", 'startedAt', x."started_at", 'heldAt', x."held_at", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', x."room_code"))) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
        and (v_after is null or (x."starts_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'title', x."title", 'location', x."location", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'status', x."status", 'startedAt', x."started_at", 'heldAt', x."held_at", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', x."room_code"))) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'title', x."title", 'location', x."location", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'status', x."status", 'startedAt', x."started_at", 'heldAt', x."held_at", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', x."room_code"))) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
        and (v_after is null or (x."starts_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'title', x."title", 'location', x."location", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'status', x."status", 'startedAt', x."started_at", 'heldAt', x."held_at", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', x."room_code"))) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'title', x."title", 'location', x."location", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'status', x."status", 'startedAt', x."started_at", 'heldAt', x."held_at", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', x."room_code"))) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'title', x."title", 'location', x."location", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'status', x."status", 'startedAt', x."started_at", 'heldAt', x."held_at", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', x."room_code"))) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or x."starts_at" >= nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."starts_at" <= nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::timestamptz)
        and (nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '') is null or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = nullif(coalesce(v_filters #>> '{attendeeId,0}', v_filters ->> 'attendeeId'), '')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_warranty_claims (
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
  v_filters jsonb := coalesce(list_warranty_claims.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_warranty_claims.tenant is not null and coalesce(better_supabase.can('tenant', list_warranty_claims.tenant, 'warranty.read'), false))) then
    raise exception 'not allowed to read warranty claims' using errcode = '42501', hint = 'WARRANTY_FORBIDDEN';
  end if;
  if exists (
    select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'status') = 'array' then v_filters -> 'status' else jsonb_build_array(v_filters -> 'status') end) s
    where s not in ('draft', 'submitted', 'approved', 'denied', 'closed')
  ) then
    raise exception 'status is not a warranty status' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'assetId') = 'array' then v_filters -> 'assetId' else jsonb_build_array(v_filters -> 'assetId') end) s
    where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  ) then
    raise exception 'assetId must be a uuid' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'WARRANTY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
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
      select 1 from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'amount') then
    raise exception 'sort is one of createdAt, amount' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'title', x."title",
    'assetId', x."asset_id",
    'supplierId', x."supplier_id",
    'manufacturer', x."manufacturer",
    'amount', x."amount"::text,
    'currency', x."currency",
    'status', x."status",
    'decision', x."decision",
    'decidedAt', x."decided_at",
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'title', x."title",
    'assetId', x."asset_id",
    'supplierId', x."supplier_id",
    'manufacturer', x."manufacturer",
    'amount', x."amount"::text,
    'currency', x."currency",
    'status', x."status",
    'decision', x."decision",
    'decidedAt', x."decided_at",
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'title', x."title",
    'assetId', x."asset_id",
    'supplierId', x."supplier_id",
    'manufacturer', x."manufacturer",
    'amount', x."amount"::text,
    'currency', x."currency",
    'status', x."status",
    'decision', x."decision",
    'decidedAt', x."decided_at",
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'title', x."title",
    'assetId', x."asset_id",
    'supplierId', x."supplier_id",
    'manufacturer', x."manufacturer",
    'amount', x."amount"::text,
    'currency', x."currency",
    'status', x."status",
    'decision', x."decision",
    'decidedAt', x."decided_at",
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'amount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'title', x."title",
    'assetId', x."asset_id",
    'supplierId', x."supplier_id",
    'manufacturer', x."manufacturer",
    'amount', x."amount"::text,
    'currency', x."currency",
    'status', x."status",
    'decision', x."decision",
    'decidedAt', x."decided_at",
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."amount")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_after is null or (x."amount", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."amount" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'amount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'title', x."title",
    'assetId', x."asset_id",
    'supplierId', x."supplier_id",
    'manufacturer', x."manufacturer",
    'amount', x."amount"::text,
    'currency', x."currency",
    'status', x."status",
    'decision', x."decision",
    'decidedAt', x."decided_at",
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."amount")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_after is null or (x."amount" <= (v_after ->> 0)::bigint and ((x."amount" < (v_after ->> 0)::bigint) or (x."amount" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."amount" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."get_warranty_claim"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_warranty_claim"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_warranty_claim"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_warranty_claim"(uuid) TO "authenticated", "service_role";
