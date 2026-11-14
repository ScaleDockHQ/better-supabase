SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.get_enrollment (
  enrollment_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_enrollment"($1) $function$;

CREATE OR REPLACE FUNCTION api.page_enrollments (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_enrollments"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_passes (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_passes"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_payroll_runs (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_payroll_runs"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_sequences (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_sequences"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_enrollment (
  enrollment_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."enrollments";
begin
  select * into v_row from "better_supabase"."enrollments" x where x."id" = get_enrollment.enrollment_id;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.read'), false))) or (v_row."user_id" is not null and coalesce(v_row."user_id" = auth.uid(), false))) then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  return "better_supabase"."enrollment_json"(v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_prescriptions (
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
  v_filters jsonb := coalesce(list_prescriptions.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_prescriptions.tenant is not null and coalesce(better_supabase.can('tenant', list_prescriptions.tenant, 'e_prescribing.read'), false))) then
    raise exception 'not allowed to read prescriptions' using errcode = '42501', hint = 'E_PRESCRIBING_FORBIDDEN';
  end if;
  if (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) and exists (
    select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'status') = 'array' then v_filters -> 'status' else jsonb_build_array(v_filters ->> 'status') end) s(v)
    where s.v not in ('draft', 'signed', 'sent', 'dispensed', 'cancelled')
  ) then
    raise exception 'status is draft, signed, sent, dispensed or cancelled' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."prescriptions" x
      where x."tenant_id" = list_prescriptions.tenant
        and (not (v_filters -> 'orderId' is not null and jsonb_typeof(v_filters -> 'orderId') <> 'null' and not (jsonb_typeof(v_filters -> 'orderId') = 'array' and jsonb_array_length(v_filters -> 'orderId') = 0)) or x."order_id" = any((case when jsonb_typeof(v_filters -> 'orderId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'orderId')) else array[v_filters ->> 'orderId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'prescriberId' is not null and jsonb_typeof(v_filters -> 'prescriberId') <> 'null' and not (jsonb_typeof(v_filters -> 'prescriberId') = 'array' and jsonb_array_length(v_filters -> 'prescriberId') = 0)) or x."prescriber_id" = any((case when jsonb_typeof(v_filters -> 'prescriberId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'prescriberId')) else array[v_filters ->> 'prescriberId'] end)::uuid[]))
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
      select 1 from "better_supabase"."prescriptions" x
      where x."tenant_id" = list_prescriptions.tenant
        and (not (v_filters -> 'orderId' is not null and jsonb_typeof(v_filters -> 'orderId') <> 'null' and not (jsonb_typeof(v_filters -> 'orderId') = 'array' and jsonb_array_length(v_filters -> 'orderId') = 0)) or x."order_id" = any((case when jsonb_typeof(v_filters -> 'orderId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'orderId')) else array[v_filters ->> 'orderId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'prescriberId' is not null and jsonb_typeof(v_filters -> 'prescriberId') <> 'null' and not (jsonb_typeof(v_filters -> 'prescriberId') = 'array' and jsonb_array_length(v_filters -> 'prescriberId') = 0)) or x."prescriber_id" = any((case when jsonb_typeof(v_filters -> 'prescriberId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'prescriberId')) else array[v_filters ->> 'prescriberId'] end)::uuid[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'signedAt') then
    raise exception 'sort is one of createdAt, signedAt' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'orderId', x."order_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'prescriberId', x."prescriber_id", 'prescriberName', x."prescriber_name", 'status', x."status", 'order', x."snapshot", 'signedBy', x."signed_by", 'signedAt', x."signed_at", 'gateway', x."gateway", 'gatewayReference', x."gateway_reference", 'sentAt', x."sent_at", 'deliveryError', x."delivery_error", 'dispensedAt', x."dispensed_at", 'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."prescriptions" x
      where x."tenant_id" = list_prescriptions.tenant
        and (not (v_filters -> 'orderId' is not null and jsonb_typeof(v_filters -> 'orderId') <> 'null' and not (jsonb_typeof(v_filters -> 'orderId') = 'array' and jsonb_array_length(v_filters -> 'orderId') = 0)) or x."order_id" = any((case when jsonb_typeof(v_filters -> 'orderId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'orderId')) else array[v_filters ->> 'orderId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'prescriberId' is not null and jsonb_typeof(v_filters -> 'prescriberId') <> 'null' and not (jsonb_typeof(v_filters -> 'prescriberId') = 'array' and jsonb_array_length(v_filters -> 'prescriberId') = 0)) or x."prescriber_id" = any((case when jsonb_typeof(v_filters -> 'prescriberId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'prescriberId')) else array[v_filters ->> 'prescriberId'] end)::uuid[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'orderId', x."order_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'prescriberId', x."prescriber_id", 'prescriberName', x."prescriber_name", 'status', x."status", 'order', x."snapshot", 'signedBy', x."signed_by", 'signedAt', x."signed_at", 'gateway', x."gateway", 'gatewayReference', x."gateway_reference", 'sentAt', x."sent_at", 'deliveryError', x."delivery_error", 'dispensedAt', x."dispensed_at", 'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."prescriptions" x
      where x."tenant_id" = list_prescriptions.tenant
        and (not (v_filters -> 'orderId' is not null and jsonb_typeof(v_filters -> 'orderId') <> 'null' and not (jsonb_typeof(v_filters -> 'orderId') = 'array' and jsonb_array_length(v_filters -> 'orderId') = 0)) or x."order_id" = any((case when jsonb_typeof(v_filters -> 'orderId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'orderId')) else array[v_filters ->> 'orderId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'prescriberId' is not null and jsonb_typeof(v_filters -> 'prescriberId') <> 'null' and not (jsonb_typeof(v_filters -> 'prescriberId') = 'array' and jsonb_array_length(v_filters -> 'prescriberId') = 0)) or x."prescriber_id" = any((case when jsonb_typeof(v_filters -> 'prescriberId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'prescriberId')) else array[v_filters ->> 'prescriberId'] end)::uuid[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'orderId', x."order_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'prescriberId', x."prescriber_id", 'prescriberName', x."prescriber_name", 'status', x."status", 'order', x."snapshot", 'signedBy', x."signed_by", 'signedAt', x."signed_at", 'gateway', x."gateway", 'gatewayReference', x."gateway_reference", 'sentAt', x."sent_at", 'deliveryError', x."delivery_error", 'dispensedAt', x."dispensed_at", 'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."prescriptions" x
      where x."tenant_id" = list_prescriptions.tenant
        and (not (v_filters -> 'orderId' is not null and jsonb_typeof(v_filters -> 'orderId') <> 'null' and not (jsonb_typeof(v_filters -> 'orderId') = 'array' and jsonb_array_length(v_filters -> 'orderId') = 0)) or x."order_id" = any((case when jsonb_typeof(v_filters -> 'orderId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'orderId')) else array[v_filters ->> 'orderId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'prescriberId' is not null and jsonb_typeof(v_filters -> 'prescriberId') <> 'null' and not (jsonb_typeof(v_filters -> 'prescriberId') = 'array' and jsonb_array_length(v_filters -> 'prescriberId') = 0)) or x."prescriber_id" = any((case when jsonb_typeof(v_filters -> 'prescriberId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'prescriberId')) else array[v_filters ->> 'prescriberId'] end)::uuid[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'orderId', x."order_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'prescriberId', x."prescriber_id", 'prescriberName', x."prescriber_name", 'status', x."status", 'order', x."snapshot", 'signedBy', x."signed_by", 'signedAt', x."signed_at", 'gateway', x."gateway", 'gatewayReference', x."gateway_reference", 'sentAt', x."sent_at", 'deliveryError', x."delivery_error", 'dispensedAt', x."dispensed_at", 'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."prescriptions" x
      where x."tenant_id" = list_prescriptions.tenant
        and (not (v_filters -> 'orderId' is not null and jsonb_typeof(v_filters -> 'orderId') <> 'null' and not (jsonb_typeof(v_filters -> 'orderId') = 'array' and jsonb_array_length(v_filters -> 'orderId') = 0)) or x."order_id" = any((case when jsonb_typeof(v_filters -> 'orderId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'orderId')) else array[v_filters ->> 'orderId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'prescriberId' is not null and jsonb_typeof(v_filters -> 'prescriberId') <> 'null' and not (jsonb_typeof(v_filters -> 'prescriberId') = 'array' and jsonb_array_length(v_filters -> 'prescriberId') = 0)) or x."prescriber_id" = any((case when jsonb_typeof(v_filters -> 'prescriberId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'prescriberId')) else array[v_filters ->> 'prescriberId'] end)::uuid[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'signedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'orderId', x."order_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'prescriberId', x."prescriber_id", 'prescriberName', x."prescriber_name", 'status', x."status", 'order', x."snapshot", 'signedBy', x."signed_by", 'signedAt', x."signed_at", 'gateway', x."gateway", 'gatewayReference', x."gateway_reference", 'sentAt', x."sent_at", 'deliveryError', x."delivery_error", 'dispensedAt', x."dispensed_at", 'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."signed_at", '-infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."prescriptions" x
      where x."tenant_id" = list_prescriptions.tenant
        and (not (v_filters -> 'orderId' is not null and jsonb_typeof(v_filters -> 'orderId') <> 'null' and not (jsonb_typeof(v_filters -> 'orderId') = 'array' and jsonb_array_length(v_filters -> 'orderId') = 0)) or x."order_id" = any((case when jsonb_typeof(v_filters -> 'orderId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'orderId')) else array[v_filters ->> 'orderId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'prescriberId' is not null and jsonb_typeof(v_filters -> 'prescriberId') <> 'null' and not (jsonb_typeof(v_filters -> 'prescriberId') = 'array' and jsonb_array_length(v_filters -> 'prescriberId') = 0)) or x."prescriber_id" = any((case when jsonb_typeof(v_filters -> 'prescriberId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'prescriberId')) else array[v_filters ->> 'prescriberId'] end)::uuid[]))
        and (v_after is null or (coalesce(x."signed_at", '-infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."signed_at", '-infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'signedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'E_PRESCRIBING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'orderId', x."order_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'prescriberId', x."prescriber_id", 'prescriberName', x."prescriber_name", 'status', x."status", 'order', x."snapshot", 'signedBy', x."signed_by", 'signedAt', x."signed_at", 'gateway', x."gateway", 'gatewayReference', x."gateway_reference", 'sentAt', x."sent_at", 'deliveryError', x."delivery_error", 'dispensedAt', x."dispensed_at", 'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."signed_at", '-infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."prescriptions" x
      where x."tenant_id" = list_prescriptions.tenant
        and (not (v_filters -> 'orderId' is not null and jsonb_typeof(v_filters -> 'orderId') <> 'null' and not (jsonb_typeof(v_filters -> 'orderId') = 'array' and jsonb_array_length(v_filters -> 'orderId') = 0)) or x."order_id" = any((case when jsonb_typeof(v_filters -> 'orderId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'orderId')) else array[v_filters ->> 'orderId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'prescriberId' is not null and jsonb_typeof(v_filters -> 'prescriberId') <> 'null' and not (jsonb_typeof(v_filters -> 'prescriberId') = 'array' and jsonb_array_length(v_filters -> 'prescriberId') = 0)) or x."prescriber_id" = any((case when jsonb_typeof(v_filters -> 'prescriberId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'prescriberId')) else array[v_filters ->> 'prescriberId'] end)::uuid[]))
        and (v_after is null or (coalesce(x."signed_at", '-infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."signed_at", '-infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."signed_at", '-infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."signed_at", '-infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."prescriptions" x
      where x."tenant_id" = list_prescriptions.tenant
        and (not (v_filters -> 'orderId' is not null and jsonb_typeof(v_filters -> 'orderId') <> 'null' and not (jsonb_typeof(v_filters -> 'orderId') = 'array' and jsonb_array_length(v_filters -> 'orderId') = 0)) or x."order_id" = any((case when jsonb_typeof(v_filters -> 'orderId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'orderId')) else array[v_filters ->> 'orderId'] end)::uuid[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'prescriberId' is not null and jsonb_typeof(v_filters -> 'prescriberId') <> 'null' and not (jsonb_typeof(v_filters -> 'prescriberId') = 'array' and jsonb_array_length(v_filters -> 'prescriberId') = 0)) or x."prescriber_id" = any((case when jsonb_typeof(v_filters -> 'prescriberId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'prescriberId')) else array[v_filters ->> 'prescriberId'] end)::uuid[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_enrollments (
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
  v_filters jsonb := coalesce(page_enrollments.filters, '{}'::jsonb);
  v_read boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', page_enrollments.tenant, 'enrollments.read'), false)));
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
  if not v_read and auth.uid() is null then
    raise exception 'not allowed to read enrollments' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'program') then
      raise exception 'facet is one of status, program' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status"::text)::text when 'program' then (x."program")::text end) as v
      from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
      select 1 from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('updatedAt', 'enrolledAt') then
    raise exception 'sort is one of updatedAt, enrolledAt' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."enrollment_json"(x."id") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."enrollment_json"(x."id") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."enrollment_json"(x."id") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."enrollment_json"(x."id") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'enrolledAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."enrollment_json"(x."id") as j, jsonb_build_array((x."enrolled_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."enrolled_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."enrolled_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'enrolledAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."enrollment_json"(x."id") as j, jsonb_build_array((x."enrolled_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."enrolled_at" <= (v_after ->> 0)::timestamptz and ((x."enrolled_at" < (v_after ->> 0)::timestamptz) or (x."enrolled_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."enrolled_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_passes (
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
  v_filters jsonb := coalesce(page_passes.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_passes.tenant, 'passes.read'), false)) then
    raise exception 'not allowed to read passes' using errcode = '42501', hint = 'PASS_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'PASS_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
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
      select 1 from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'validFrom', 'validUntil') then
    raise exception 'sort is one of createdAt, validFrom, validUntil' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'validFrom' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."starts_at" >= (v_after ->> 0)::timestamptz and ((x."starts_at" > (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."starts_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'validFrom' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."starts_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."starts_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'validUntil' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as j, jsonb_build_array((coalesce(x."expires_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (coalesce(x."expires_at", 'infinity'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(x."expires_at", 'infinity'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(x."expires_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."expires_at", 'infinity'::timestamptz) asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'validUntil' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PASS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as j, jsonb_build_array((coalesce(x."expires_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (coalesce(x."expires_at", 'infinity'::timestamptz), x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."expires_at", 'infinity'::timestamptz) desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."passes" x
      where x."tenant_id" = page_passes.tenant
        and (not (v_filters -> 'holderUserId' is not null and jsonb_typeof(v_filters -> 'holderUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'holderUserId') = 'array' and jsonb_array_length(v_filters -> 'holderUserId') = 0)) or x."holder_id" = any((case when jsonb_typeof(v_filters -> 'holderUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'holderUserId')) else array[v_filters ->> 'holderUserId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_payroll_runs (
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
  v_filters jsonb := coalesce(page_payroll_runs.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_payroll_runs.tenant is not null and coalesce(better_supabase.can('tenant', page_payroll_runs.tenant, 'payroll_export.read'), false))) then
    raise exception 'not allowed to do this with payroll runs' using errcode = '42501', hint = 'PAYROLL_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status"::text)::text end) as v
      from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
      select 1 from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('periodFrom', 'createdAt') then
    raise exception 'sort is one of periodFrom, createdAt' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'periodFrom', x."period_from", 'periodTo', x."period_to", 'label', x."label", 'status', x."status", 'format', x."format", 'checksum', x."checksum", 'exportedAt', x."exported_at", 'exportedBy', x."exported_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = x."id")) as j, jsonb_build_array((x."period_from")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."period_from" >= (v_after ->> 0)::date and ((x."period_from" > (v_after ->> 0)::date) or (x."period_from" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."period_from" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."period_from" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'periodFrom', x."period_from", 'periodTo', x."period_to", 'label', x."label", 'status', x."status", 'format', x."format", 'checksum', x."checksum", 'exportedAt', x."exported_at", 'exportedBy', x."exported_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = x."id")) as j, jsonb_build_array((x."period_from")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."period_from" <= (v_after ->> 0)::date and ((x."period_from" < (v_after ->> 0)::date) or (x."period_from" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."period_from" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."period_from" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'periodFrom' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'periodFrom', x."period_from", 'periodTo', x."period_to", 'label', x."label", 'status', x."status", 'format', x."format", 'checksum', x."checksum", 'exportedAt', x."exported_at", 'exportedBy', x."exported_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = x."id")) as j, jsonb_build_array((x."period_from")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."period_from" >= (v_after ->> 0)::date and ((x."period_from" > (v_after ->> 0)::date) or (x."period_from" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."period_from" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."period_from" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'periodFrom' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'periodFrom', x."period_from", 'periodTo', x."period_to", 'label', x."label", 'status', x."status", 'format', x."format", 'checksum', x."checksum", 'exportedAt', x."exported_at", 'exportedBy', x."exported_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = x."id")) as j, jsonb_build_array((x."period_from")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."period_from" <= (v_after ->> 0)::date and ((x."period_from" < (v_after ->> 0)::date) or (x."period_from" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."period_from" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."period_from" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'periodFrom', x."period_from", 'periodTo', x."period_to", 'label', x."label", 'status', x."status", 'format', x."format", 'checksum', x."checksum", 'exportedAt', x."exported_at", 'exportedBy', x."exported_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PAYROLL_RUN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'periodFrom', x."period_from", 'periodTo', x."period_to", 'label', x."label", 'status', x."status", 'format', x."format", 'checksum', x."checksum", 'exportedAt', x."exported_at", 'exportedBy', x."exported_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lineCount', (select count(*) from "better_supabase"."payroll_lines" y where y."run_id" = x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
      select 1 from "better_supabase"."payroll_runs" x
      where x."tenant_id" = page_payroll_runs.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_sequences (
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
  v_filters jsonb := coalesce(page_sequences.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_sequences.tenant is not null and coalesce(better_supabase.can('tenant', page_sequences.tenant, 'sequences.read'), false))) then
    raise exception 'not allowed to read sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status"::text)::text end) as v
      from "better_supabase"."sequences" x
      where x."tenant_id" = page_sequences.tenant
        and ((v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text <> 'archived')
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
      select 1 from "better_supabase"."sequences" x
      where x."tenant_id" = page_sequences.tenant
        and ((v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text <> 'archived')
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'updatedAt') then
    raise exception 'sort is one of name, updatedAt' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'status', x."status", 'exitOnReply', x."exit_on_reply", 'accountId', x."mail_account_id", 'steps', x."steps", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'active'), 'paused', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'cancelled'),
      'replied', count(*) filter (where m."status" = 'cancelled' and m."cancel_reason" = 'replied'))
    from "better_supabase"."enrollments" m where m."sequence_id" = x."id")) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."sequences" x
      where x."tenant_id" = page_sequences.tenant
        and ((v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text <> 'archived')
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'status', x."status", 'exitOnReply', x."exit_on_reply", 'accountId', x."mail_account_id", 'steps', x."steps", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'active'), 'paused', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'cancelled'),
      'replied', count(*) filter (where m."status" = 'cancelled' and m."cancel_reason" = 'replied'))
    from "better_supabase"."enrollments" m where m."sequence_id" = x."id")) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."sequences" x
      where x."tenant_id" = page_sequences.tenant
        and ((v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text <> 'archived')
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'status', x."status", 'exitOnReply', x."exit_on_reply", 'accountId', x."mail_account_id", 'steps', x."steps", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'active'), 'paused', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'cancelled'),
      'replied', count(*) filter (where m."status" = 'cancelled' and m."cancel_reason" = 'replied'))
    from "better_supabase"."enrollments" m where m."sequence_id" = x."id")) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."sequences" x
      where x."tenant_id" = page_sequences.tenant
        and ((v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text <> 'archived')
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'status', x."status", 'exitOnReply', x."exit_on_reply", 'accountId', x."mail_account_id", 'steps', x."steps", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'active'), 'paused', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'cancelled'),
      'replied', count(*) filter (where m."status" = 'cancelled' and m."cancel_reason" = 'replied'))
    from "better_supabase"."enrollments" m where m."sequence_id" = x."id")) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."sequences" x
      where x."tenant_id" = page_sequences.tenant
        and ((v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text <> 'archived')
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'status', x."status", 'exitOnReply', x."exit_on_reply", 'accountId', x."mail_account_id", 'steps', x."steps", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'active'), 'paused', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'cancelled'),
      'replied', count(*) filter (where m."status" = 'cancelled' and m."cancel_reason" = 'replied'))
    from "better_supabase"."enrollments" m where m."sequence_id" = x."id")) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."sequences" x
      where x."tenant_id" = page_sequences.tenant
        and ((v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text <> 'archived')
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'status', x."status", 'exitOnReply', x."exit_on_reply", 'accountId', x."mail_account_id", 'steps', x."steps", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'active'), 'paused', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'cancelled'),
      'replied', count(*) filter (where m."status" = 'cancelled' and m."cancel_reason" = 'replied'))
    from "better_supabase"."enrollments" m where m."sequence_id" = x."id")) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."sequences" x
      where x."tenant_id" = page_sequences.tenant
        and ((v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text <> 'archived')
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."sequences" x
      where x."tenant_id" = page_sequences.tenant
        and ((v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text <> 'archived')
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."get_enrollment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_enrollment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_enrollments"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_enrollments"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_passes"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_passes"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_payroll_runs"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_payroll_runs"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_sequences"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_sequences"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_enrollment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_enrollment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_enrollments"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_enrollments"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_passes"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_passes"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_payroll_runs"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_payroll_runs"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_sequences"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_sequences"(uuid, jsonb) TO "authenticated", "service_role";
