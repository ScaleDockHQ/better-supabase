SET local check_function_bodies = off;

DROP TRIGGER "bsb_search_qualification_type_index" ON "better_supabase"."qualification_types";

CREATE OR REPLACE FUNCTION api.get_inventory_level (
  level_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_inventory_level"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_inventory_lot (
  lot_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_inventory_lot"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_inventory_movement (
  movement_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_inventory_movement"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_qualification_type (
  type_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_qualification_type"($1) $function$;

CREATE OR REPLACE FUNCTION api.page_attachments (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_attachments"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_drive_documents (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_drive_documents"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_form_submissions (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_form_submissions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_inventory_levels (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_inventory_levels"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_inventory_lots (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_inventory_lots"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_inventory_movements (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_inventory_movements"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_qualification_types (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_qualification_types"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_signature_requests (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_signature_requests"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_templates (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_templates"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_versions (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_versions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_inventory_level (
  level_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_row jsonb;
begin
  select jsonb_build_object(
      'id', x."variant_id"::text || ':' || x."location_id"::text,
      'variantId', x."variant_id",
      'locationId', x."location_id",
      'onHand', x."on_hand"::text,
      'allocated', x."reserved"::text,
      'available', x."available"::text,
      'incoming', x."incoming"::text,
      'reorderPoint', x."reorder_point"::text,
      'status', case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end) into v_row
  from "better_supabase"."stock_levels" x
  where x."variant_id"::text || ':' || x."location_id"::text = get_inventory_level.level_id;
  if v_row is null then
    raise exception 'no such stock level' using errcode = 'P0002', hint = 'INVENTORY_LEVEL_NOT_FOUND';
  end if;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_inventory_lot (
  lot_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row jsonb;
  v_tenant uuid;
begin
  select x."tenant_id", jsonb_build_object('id', x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, ''), 'lotId', x.lot_pk, 'code', x.lot_code, 'variantId', x.lot_variant, 'locationId', x."location_id", 'binId', x."bin_id", 'expiresOn', x.lot_expires_on, 'onHand', x."on_hand"::text, 'expiry', case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end) into v_tenant, v_row
  from (select y.*, lo."id" as lot_pk, lo."code" as lot_code, lo."variant_id" as lot_variant, lo."expires_on" as lot_expires_on from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id" where y."on_hand" > 0) x
  where x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '') = get_inventory_lot.lot_id;
  if v_row is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.read'), false)) then
    raise exception 'no such lot with stock' using errcode = 'P0002', hint = 'INVENTORY_LOT_NOT_FOUND';
  end if;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_inventory_movement (
  movement_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_row jsonb;
begin
  select jsonb_build_object(
      'id', x."id",
      'kind', x."kind",
      'variantId', x."metadata" ->> 'variantId',
      'locationId', x."metadata" ->> 'locationId',
      'binId', x."metadata" ->> 'binId',
      'lotId', x."metadata" ->> 'lotId',
      'quantity', x."metadata" ->> 'quantity',
      'documentType', x."reference_type",
      'documentId', x."reference_id",
      'effectiveAt', x."effective_at") into v_row
  from "better_supabase"."ledger_transactions" x
  where x."id" = get_inventory_movement.movement_id
    and x."kind" like 'stock.%';
  if v_row is null then
    raise exception 'no such stock movement' using errcode = 'P0002', hint = 'INVENTORY_MOVEMENT_NOT_FOUND';
  end if;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_qualification_type (
  type_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."qualification_types"%rowtype;
begin
  select * into v_row from "better_supabase"."qualification_types" x where x."id" = get_qualification_type.type_id;
  if not found then
    raise exception 'qualification type not found' using errcode = 'P0002', hint = 'QUALIFICATION_TYPE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'holderTypes', to_jsonb(v_row."holder_types"), 'validForMonths', v_row."valid_for_months", 'evidenceRequired', v_row."evidence_required", 'courseId', v_row."course_id", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_forms (
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
  v_filters jsonb := coalesce(list_forms.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 200), 1), 500);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_forms.tenant, 'forms.read'), false)) then
    raise exception 'not allowed to read forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'FORM_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."forms" x
      where x."tenant_id" = list_forms.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
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
      select 1 from "better_supabase"."forms" x
      where x."tenant_id" = list_forms.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'title', 'key') then
    raise exception 'sort is one of createdAt, title, key' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'status', x."status", 'currentVersionId', x."current_version_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forms" x
      where x."tenant_id" = list_forms.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'status', x."status", 'currentVersionId', x."current_version_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forms" x
      where x."tenant_id" = list_forms.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'status', x."status", 'currentVersionId', x."current_version_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forms" x
      where x."tenant_id" = list_forms.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'status', x."status", 'currentVersionId', x."current_version_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forms" x
      where x."tenant_id" = list_forms.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'status', x."status", 'currentVersionId', x."current_version_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forms" x
      where x."tenant_id" = list_forms.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."title", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."title" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'status', x."status", 'currentVersionId', x."current_version_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forms" x
      where x."tenant_id" = list_forms.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."title" <= (v_after ->> 0)::text and ((x."title" < (v_after ->> 0)::text) or (x."title" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."title" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'status', x."status", 'currentVersionId', x."current_version_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forms" x
      where x."tenant_id" = list_forms.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'status', x."status", 'currentVersionId', x."current_version_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forms" x
      where x."tenant_id" = list_forms.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."forms" x
      where x."tenant_id" = list_forms.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_attachments (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_attachments.filters, '{}'::jsonb);
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
  if v_facet is null and not v_count and nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '') is not null and nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '') is not null then
    perform "better_supabase"."record_subject_read"(nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), ''), nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), ''), null, 'attachments', 'page_attachments');
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'ATTACHMENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'subjectType') then
      raise exception 'facet is one of status, subjectType' using errcode = '22023', hint = 'ATTACHMENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status"::text)::text when 'subjectType' then (x."subject_type")::text end) as v
      from "better_supabase"."attachments" x
      where x."tenant_id" is not distinct from page_attachments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentTypeId' is not null and jsonb_typeof(v_filters -> 'documentTypeId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentTypeId') = 'array' and jsonb_array_length(v_filters -> 'documentTypeId') = 0)) or x."document_type_id" = any((case when jsonb_typeof(v_filters -> 'documentTypeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentTypeId')) else array[v_filters ->> 'documentTypeId'] end)::uuid[]))
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
      select 1 from "better_supabase"."attachments" x
      where x."tenant_id" is not distinct from page_attachments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentTypeId' is not null and jsonb_typeof(v_filters -> 'documentTypeId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentTypeId') = 'array' and jsonb_array_length(v_filters -> 'documentTypeId') = 0)) or x."document_type_id" = any((case when jsonb_typeof(v_filters -> 'documentTypeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentTypeId')) else array[v_filters ->> 'documentTypeId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'name', 'size') then
    raise exception 'sort is one of createdAt, name, size' using errcode = '22023', hint = 'ATTACHMENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'ATTACHMENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ATTACHMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('object_path', (case when x."version" > 1 then x."object_path" || '-v' || x."version"::text else x."object_path" end))) || jsonb_build_object('author', "better_supabase"."attachment_authors"(array[x."id"]) -> x."id"::text) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."attachments" x
      where x."tenant_id" is not distinct from page_attachments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentTypeId' is not null and jsonb_typeof(v_filters -> 'documentTypeId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentTypeId') = 'array' and jsonb_array_length(v_filters -> 'documentTypeId') = 0)) or x."document_type_id" = any((case when jsonb_typeof(v_filters -> 'documentTypeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentTypeId')) else array[v_filters ->> 'documentTypeId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ATTACHMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('object_path', (case when x."version" > 1 then x."object_path" || '-v' || x."version"::text else x."object_path" end))) || jsonb_build_object('author', "better_supabase"."attachment_authors"(array[x."id"]) -> x."id"::text) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."attachments" x
      where x."tenant_id" is not distinct from page_attachments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentTypeId' is not null and jsonb_typeof(v_filters -> 'documentTypeId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentTypeId') = 'array' and jsonb_array_length(v_filters -> 'documentTypeId') = 0)) or x."document_type_id" = any((case when jsonb_typeof(v_filters -> 'documentTypeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentTypeId')) else array[v_filters ->> 'documentTypeId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ATTACHMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('object_path', (case when x."version" > 1 then x."object_path" || '-v' || x."version"::text else x."object_path" end))) || jsonb_build_object('author', "better_supabase"."attachment_authors"(array[x."id"]) -> x."id"::text) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."attachments" x
      where x."tenant_id" is not distinct from page_attachments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentTypeId' is not null and jsonb_typeof(v_filters -> 'documentTypeId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentTypeId') = 'array' and jsonb_array_length(v_filters -> 'documentTypeId') = 0)) or x."document_type_id" = any((case when jsonb_typeof(v_filters -> 'documentTypeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentTypeId')) else array[v_filters ->> 'documentTypeId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ATTACHMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('object_path', (case when x."version" > 1 then x."object_path" || '-v' || x."version"::text else x."object_path" end))) || jsonb_build_object('author', "better_supabase"."attachment_authors"(array[x."id"]) -> x."id"::text) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."attachments" x
      where x."tenant_id" is not distinct from page_attachments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentTypeId' is not null and jsonb_typeof(v_filters -> 'documentTypeId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentTypeId') = 'array' and jsonb_array_length(v_filters -> 'documentTypeId') = 0)) or x."document_type_id" = any((case when jsonb_typeof(v_filters -> 'documentTypeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentTypeId')) else array[v_filters ->> 'documentTypeId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ATTACHMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('object_path', (case when x."version" > 1 then x."object_path" || '-v' || x."version"::text else x."object_path" end))) || jsonb_build_object('author', "better_supabase"."attachment_authors"(array[x."id"]) -> x."id"::text) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."attachments" x
      where x."tenant_id" is not distinct from page_attachments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentTypeId' is not null and jsonb_typeof(v_filters -> 'documentTypeId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentTypeId') = 'array' and jsonb_array_length(v_filters -> 'documentTypeId') = 0)) or x."document_type_id" = any((case when jsonb_typeof(v_filters -> 'documentTypeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentTypeId')) else array[v_filters ->> 'documentTypeId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ATTACHMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('object_path', (case when x."version" > 1 then x."object_path" || '-v' || x."version"::text else x."object_path" end))) || jsonb_build_object('author', "better_supabase"."attachment_authors"(array[x."id"]) -> x."id"::text) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."attachments" x
      where x."tenant_id" is not distinct from page_attachments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentTypeId' is not null and jsonb_typeof(v_filters -> 'documentTypeId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentTypeId') = 'array' and jsonb_array_length(v_filters -> 'documentTypeId') = 0)) or x."document_type_id" = any((case when jsonb_typeof(v_filters -> 'documentTypeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentTypeId')) else array[v_filters ->> 'documentTypeId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'size' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ATTACHMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('object_path', (case when x."version" > 1 then x."object_path" || '-v' || x."version"::text else x."object_path" end))) || jsonb_build_object('author', "better_supabase"."attachment_authors"(array[x."id"]) -> x."id"::text) as j, jsonb_build_array((coalesce(x."size", 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."attachments" x
      where x."tenant_id" is not distinct from page_attachments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentTypeId' is not null and jsonb_typeof(v_filters -> 'documentTypeId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentTypeId') = 'array' and jsonb_array_length(v_filters -> 'documentTypeId') = 0)) or x."document_type_id" = any((case when jsonb_typeof(v_filters -> 'documentTypeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentTypeId')) else array[v_filters ->> 'documentTypeId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (coalesce(x."size", 0), x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by coalesce(x."size", 0) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'size' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ATTACHMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (to_jsonb(x) || jsonb_build_object('object_path', (case when x."version" > 1 then x."object_path" || '-v' || x."version"::text else x."object_path" end))) || jsonb_build_object('author', "better_supabase"."attachment_authors"(array[x."id"]) -> x."id"::text) as j, jsonb_build_array((coalesce(x."size", 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."attachments" x
      where x."tenant_id" is not distinct from page_attachments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentTypeId' is not null and jsonb_typeof(v_filters -> 'documentTypeId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentTypeId') = 'array' and jsonb_array_length(v_filters -> 'documentTypeId') = 0)) or x."document_type_id" = any((case when jsonb_typeof(v_filters -> 'documentTypeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentTypeId')) else array[v_filters ->> 'documentTypeId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (coalesce(x."size", 0) <= (v_after ->> 0)::bigint and ((coalesce(x."size", 0) < (v_after ->> 0)::bigint) or (coalesce(x."size", 0) = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."size", 0) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."attachments" x
      where x."tenant_id" is not distinct from page_attachments.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'documentTypeId' is not null and jsonb_typeof(v_filters -> 'documentTypeId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentTypeId') = 'array' and jsonb_array_length(v_filters -> 'documentTypeId') = 0)) or x."document_type_id" = any((case when jsonb_typeof(v_filters -> 'documentTypeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentTypeId')) else array[v_filters ->> 'documentTypeId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_drive_documents (
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
  v_filters jsonb := coalesce(page_drive_documents.filters, '{}'::jsonb);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'DRIVE_DOCUMENT_FILTER_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('type', 'status', 'review') then
      raise exception 'facet is one of type, status, review' using errcode = '22023', hint = 'DRIVE_DOCUMENT_FILTER_INVALID';
    end if;
    with s as (
      select (case v_facet when 'type' then (x."document_type")::text when 'status' then (x."document_status")::text when 'review' then (case when x."document_status" = 'effective' and x."next_review_on" <= current_date then 'due' else 'ok' end)::text end) as v
      from "better_supabase"."drive_nodes" x
      where x."tenant_id" = page_drive_documents.tenant
        and x."document_status" is not null
        and x."archived_at" is null
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."document_status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."document_owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'review' is not null and jsonb_typeof(v_filters -> 'review') <> 'null' and not (jsonb_typeof(v_filters -> 'review') = 'array' and jsonb_array_length(v_filters -> 'review') = 0)) or case when x."document_status" = 'effective' and x."next_review_on" <= current_date then 'due' else 'ok' end = any((case when jsonb_typeof(v_filters -> 'review') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'review')) else array[v_filters ->> 'review'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or (x."document_status" = 'effective' and x."next_review_on" <= current_date))
        and (v_search is null or x."document_number" ilike v_search or x."name" ilike v_search)
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
      select 1 from "better_supabase"."drive_nodes" x
      where x."tenant_id" = page_drive_documents.tenant
        and x."document_status" is not null
        and x."archived_at" is null
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."document_status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."document_owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'review' is not null and jsonb_typeof(v_filters -> 'review') <> 'null' and not (jsonb_typeof(v_filters -> 'review') = 'array' and jsonb_array_length(v_filters -> 'review') = 0)) or case when x."document_status" = 'effective' and x."next_review_on" <= current_date then 'due' else 'ok' end = any((case when jsonb_typeof(v_filters -> 'review') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'review')) else array[v_filters ->> 'review'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or (x."document_status" = 'effective' and x."next_review_on" <= current_date))
        and (v_search is null or x."document_number" ilike v_search or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('number', 'name', 'nextReviewOn') then
    raise exception 'sort is one of number, name, nextReviewOn' using errcode = '22023', hint = 'DRIVE_DOCUMENT_FILTER_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'DRIVE_DOCUMENT_FILTER_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DRIVE_DOCUMENT_FILTER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, ("better_supabase"."drive_node_json"(x) || jsonb_build_object('role', "better_supabase"."drive_role"((x)."id"), 'readOnly', (coalesce((x)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((x)."id"), 'downloadable', "better_supabase"."drive_can_download"((x)."id"))) as j, jsonb_build_array((x."document_number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."drive_nodes" x
      where x."tenant_id" = page_drive_documents.tenant
        and x."document_status" is not null
        and x."archived_at" is null
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."document_status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."document_owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'review' is not null and jsonb_typeof(v_filters -> 'review') <> 'null' and not (jsonb_typeof(v_filters -> 'review') = 'array' and jsonb_array_length(v_filters -> 'review') = 0)) or case when x."document_status" = 'effective' and x."next_review_on" <= current_date then 'due' else 'ok' end = any((case when jsonb_typeof(v_filters -> 'review') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'review')) else array[v_filters ->> 'review'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or (x."document_status" = 'effective' and x."next_review_on" <= current_date))
        and (v_search is null or x."document_number" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."document_number", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."document_number" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DRIVE_DOCUMENT_FILTER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, ("better_supabase"."drive_node_json"(x) || jsonb_build_object('role', "better_supabase"."drive_role"((x)."id"), 'readOnly', (coalesce((x)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((x)."id"), 'downloadable', "better_supabase"."drive_can_download"((x)."id"))) as j, jsonb_build_array((x."document_number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."drive_nodes" x
      where x."tenant_id" = page_drive_documents.tenant
        and x."document_status" is not null
        and x."archived_at" is null
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."document_status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."document_owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'review' is not null and jsonb_typeof(v_filters -> 'review') <> 'null' and not (jsonb_typeof(v_filters -> 'review') = 'array' and jsonb_array_length(v_filters -> 'review') = 0)) or case when x."document_status" = 'effective' and x."next_review_on" <= current_date then 'due' else 'ok' end = any((case when jsonb_typeof(v_filters -> 'review') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'review')) else array[v_filters ->> 'review'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or (x."document_status" = 'effective' and x."next_review_on" <= current_date))
        and (v_search is null or x."document_number" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."document_number" <= (v_after ->> 0)::text and ((x."document_number" < (v_after ->> 0)::text) or (x."document_number" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."document_number" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DRIVE_DOCUMENT_FILTER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, ("better_supabase"."drive_node_json"(x) || jsonb_build_object('role', "better_supabase"."drive_role"((x)."id"), 'readOnly', (coalesce((x)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((x)."id"), 'downloadable', "better_supabase"."drive_can_download"((x)."id"))) as j, jsonb_build_array((x."document_number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."drive_nodes" x
      where x."tenant_id" = page_drive_documents.tenant
        and x."document_status" is not null
        and x."archived_at" is null
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."document_status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."document_owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'review' is not null and jsonb_typeof(v_filters -> 'review') <> 'null' and not (jsonb_typeof(v_filters -> 'review') = 'array' and jsonb_array_length(v_filters -> 'review') = 0)) or case when x."document_status" = 'effective' and x."next_review_on" <= current_date then 'due' else 'ok' end = any((case when jsonb_typeof(v_filters -> 'review') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'review')) else array[v_filters ->> 'review'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or (x."document_status" = 'effective' and x."next_review_on" <= current_date))
        and (v_search is null or x."document_number" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."document_number", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."document_number" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DRIVE_DOCUMENT_FILTER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, ("better_supabase"."drive_node_json"(x) || jsonb_build_object('role', "better_supabase"."drive_role"((x)."id"), 'readOnly', (coalesce((x)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((x)."id"), 'downloadable', "better_supabase"."drive_can_download"((x)."id"))) as j, jsonb_build_array((x."document_number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."drive_nodes" x
      where x."tenant_id" = page_drive_documents.tenant
        and x."document_status" is not null
        and x."archived_at" is null
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."document_status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."document_owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'review' is not null and jsonb_typeof(v_filters -> 'review') <> 'null' and not (jsonb_typeof(v_filters -> 'review') = 'array' and jsonb_array_length(v_filters -> 'review') = 0)) or case when x."document_status" = 'effective' and x."next_review_on" <= current_date then 'due' else 'ok' end = any((case when jsonb_typeof(v_filters -> 'review') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'review')) else array[v_filters ->> 'review'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or (x."document_status" = 'effective' and x."next_review_on" <= current_date))
        and (v_search is null or x."document_number" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."document_number" <= (v_after ->> 0)::text and ((x."document_number" < (v_after ->> 0)::text) or (x."document_number" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."document_number" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DRIVE_DOCUMENT_FILTER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, ("better_supabase"."drive_node_json"(x) || jsonb_build_object('role', "better_supabase"."drive_role"((x)."id"), 'readOnly', (coalesce((x)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((x)."id"), 'downloadable', "better_supabase"."drive_can_download"((x)."id"))) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."drive_nodes" x
      where x."tenant_id" = page_drive_documents.tenant
        and x."document_status" is not null
        and x."archived_at" is null
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."document_status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."document_owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'review' is not null and jsonb_typeof(v_filters -> 'review') <> 'null' and not (jsonb_typeof(v_filters -> 'review') = 'array' and jsonb_array_length(v_filters -> 'review') = 0)) or case when x."document_status" = 'effective' and x."next_review_on" <= current_date then 'due' else 'ok' end = any((case when jsonb_typeof(v_filters -> 'review') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'review')) else array[v_filters ->> 'review'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or (x."document_status" = 'effective' and x."next_review_on" <= current_date))
        and (v_search is null or x."document_number" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DRIVE_DOCUMENT_FILTER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, ("better_supabase"."drive_node_json"(x) || jsonb_build_object('role', "better_supabase"."drive_role"((x)."id"), 'readOnly', (coalesce((x)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((x)."id"), 'downloadable', "better_supabase"."drive_can_download"((x)."id"))) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."drive_nodes" x
      where x."tenant_id" = page_drive_documents.tenant
        and x."document_status" is not null
        and x."archived_at" is null
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."document_status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."document_owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'review' is not null and jsonb_typeof(v_filters -> 'review') <> 'null' and not (jsonb_typeof(v_filters -> 'review') = 'array' and jsonb_array_length(v_filters -> 'review') = 0)) or case when x."document_status" = 'effective' and x."next_review_on" <= current_date then 'due' else 'ok' end = any((case when jsonb_typeof(v_filters -> 'review') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'review')) else array[v_filters ->> 'review'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or (x."document_status" = 'effective' and x."next_review_on" <= current_date))
        and (v_search is null or x."document_number" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'nextReviewOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DRIVE_DOCUMENT_FILTER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, ("better_supabase"."drive_node_json"(x) || jsonb_build_object('role', "better_supabase"."drive_role"((x)."id"), 'readOnly', (coalesce((x)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((x)."id"), 'downloadable', "better_supabase"."drive_can_download"((x)."id"))) as j, jsonb_build_array((coalesce(x."next_review_on", date '9999-12-31'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."drive_nodes" x
      where x."tenant_id" = page_drive_documents.tenant
        and x."document_status" is not null
        and x."archived_at" is null
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."document_status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."document_owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'review' is not null and jsonb_typeof(v_filters -> 'review') <> 'null' and not (jsonb_typeof(v_filters -> 'review') = 'array' and jsonb_array_length(v_filters -> 'review') = 0)) or case when x."document_status" = 'effective' and x."next_review_on" <= current_date then 'due' else 'ok' end = any((case when jsonb_typeof(v_filters -> 'review') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'review')) else array[v_filters ->> 'review'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or (x."document_status" = 'effective' and x."next_review_on" <= current_date))
        and (v_search is null or x."document_number" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (coalesce(x."next_review_on", date '9999-12-31'), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."next_review_on", date '9999-12-31') asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'nextReviewOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DRIVE_DOCUMENT_FILTER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, ("better_supabase"."drive_node_json"(x) || jsonb_build_object('role', "better_supabase"."drive_role"((x)."id"), 'readOnly', (coalesce((x)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((x)."id"), 'downloadable', "better_supabase"."drive_can_download"((x)."id"))) as j, jsonb_build_array((coalesce(x."next_review_on", date '9999-12-31'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."drive_nodes" x
      where x."tenant_id" = page_drive_documents.tenant
        and x."document_status" is not null
        and x."archived_at" is null
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."document_status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."document_owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'review' is not null and jsonb_typeof(v_filters -> 'review') <> 'null' and not (jsonb_typeof(v_filters -> 'review') = 'array' and jsonb_array_length(v_filters -> 'review') = 0)) or case when x."document_status" = 'effective' and x."next_review_on" <= current_date then 'due' else 'ok' end = any((case when jsonb_typeof(v_filters -> 'review') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'review')) else array[v_filters ->> 'review'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or (x."document_status" = 'effective' and x."next_review_on" <= current_date))
        and (v_search is null or x."document_number" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (coalesce(x."next_review_on", date '9999-12-31') <= (v_after ->> 0)::date and ((coalesce(x."next_review_on", date '9999-12-31') < (v_after ->> 0)::date) or (coalesce(x."next_review_on", date '9999-12-31') = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."next_review_on", date '9999-12-31') desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."drive_nodes" x
      where x."tenant_id" = page_drive_documents.tenant
        and x."document_status" is not null
        and x."archived_at" is null
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."document_type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."document_status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."document_owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'review' is not null and jsonb_typeof(v_filters -> 'review') <> 'null' and not (jsonb_typeof(v_filters -> 'review') = 'array' and jsonb_array_length(v_filters -> 'review') = 0)) or case when x."document_status" = 'effective' and x."next_review_on" <= current_date then 'due' else 'ok' end = any((case when jsonb_typeof(v_filters -> 'review') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'review')) else array[v_filters ->> 'review'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{reviewDue,0}', v_filters ->> 'reviewDue'), '') = 'true', false) or (x."document_status" = 'effective' and x."next_review_on" <= current_date))
        and (v_search is null or x."document_number" ilike v_search or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_form_submissions (
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
  v_filters jsonb := coalesce(page_form_submissions.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_all boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_form_submissions.tenant, 'forms.review'), false);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'formId') then
      raise exception 'facet is one of status, formId' using errcode = '22023', hint = 'FORM_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'formId' then (x."form_id"::text)::text end) as v
      from "better_supabase"."form_submissions" x
      where x."tenant_id" = page_form_submissions.tenant
        and (not (v_filters -> 'formId' is not null and jsonb_typeof(v_filters -> 'formId') <> 'null' and not (jsonb_typeof(v_filters -> 'formId') = 'array' and jsonb_array_length(v_filters -> 'formId') = 0)) or x."form_id" = any((case when jsonb_typeof(v_filters -> 'formId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'formId')) else array[v_filters ->> 'formId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'respondentId' is not null and jsonb_typeof(v_filters -> 'respondentId') <> 'null' and not (jsonb_typeof(v_filters -> 'respondentId') = 'array' and jsonb_array_length(v_filters -> 'respondentId') = 0)) or x."respondent_id" = any((case when jsonb_typeof(v_filters -> 'respondentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'respondentId')) else array[v_filters ->> 'respondentId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."answers"::text ilike v_search)
        and (v_all or x."respondent_id" = auth.uid())
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
      select 1 from "better_supabase"."form_submissions" x
      where x."tenant_id" = page_form_submissions.tenant
        and (not (v_filters -> 'formId' is not null and jsonb_typeof(v_filters -> 'formId') <> 'null' and not (jsonb_typeof(v_filters -> 'formId') = 'array' and jsonb_array_length(v_filters -> 'formId') = 0)) or x."form_id" = any((case when jsonb_typeof(v_filters -> 'formId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'formId')) else array[v_filters ->> 'formId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'respondentId' is not null and jsonb_typeof(v_filters -> 'respondentId') <> 'null' and not (jsonb_typeof(v_filters -> 'respondentId') = 'array' and jsonb_array_length(v_filters -> 'respondentId') = 0)) or x."respondent_id" = any((case when jsonb_typeof(v_filters -> 'respondentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'respondentId')) else array[v_filters ->> 'respondentId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."answers"::text ilike v_search)
        and (v_all or x."respondent_id" = auth.uid())
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'submittedAt') then
    raise exception 'sort is one of createdAt, submittedAt' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'formId', x."form_id", 'versionId', x."version_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'respondentId', x."respondent_id", 'answers', x."answers", 'status', x."status", 'source', x."source", 'reviewedBy', x."reviewed_by", 'reviewedAt', x."reviewed_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'submittedAt', x."submitted_at", 'updatedAt', x."updated_at", 'score', x."score", 'maxScore', x."max_score", 'passed', x."passed") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."form_submissions" x
      where x."tenant_id" = page_form_submissions.tenant
        and (not (v_filters -> 'formId' is not null and jsonb_typeof(v_filters -> 'formId') <> 'null' and not (jsonb_typeof(v_filters -> 'formId') = 'array' and jsonb_array_length(v_filters -> 'formId') = 0)) or x."form_id" = any((case when jsonb_typeof(v_filters -> 'formId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'formId')) else array[v_filters ->> 'formId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'respondentId' is not null and jsonb_typeof(v_filters -> 'respondentId') <> 'null' and not (jsonb_typeof(v_filters -> 'respondentId') = 'array' and jsonb_array_length(v_filters -> 'respondentId') = 0)) or x."respondent_id" = any((case when jsonb_typeof(v_filters -> 'respondentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'respondentId')) else array[v_filters ->> 'respondentId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."answers"::text ilike v_search)
        and (v_all or x."respondent_id" = auth.uid())
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'formId', x."form_id", 'versionId', x."version_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'respondentId', x."respondent_id", 'answers', x."answers", 'status', x."status", 'source', x."source", 'reviewedBy', x."reviewed_by", 'reviewedAt', x."reviewed_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'submittedAt', x."submitted_at", 'updatedAt', x."updated_at", 'score', x."score", 'maxScore', x."max_score", 'passed', x."passed") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."form_submissions" x
      where x."tenant_id" = page_form_submissions.tenant
        and (not (v_filters -> 'formId' is not null and jsonb_typeof(v_filters -> 'formId') <> 'null' and not (jsonb_typeof(v_filters -> 'formId') = 'array' and jsonb_array_length(v_filters -> 'formId') = 0)) or x."form_id" = any((case when jsonb_typeof(v_filters -> 'formId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'formId')) else array[v_filters ->> 'formId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'respondentId' is not null and jsonb_typeof(v_filters -> 'respondentId') <> 'null' and not (jsonb_typeof(v_filters -> 'respondentId') = 'array' and jsonb_array_length(v_filters -> 'respondentId') = 0)) or x."respondent_id" = any((case when jsonb_typeof(v_filters -> 'respondentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'respondentId')) else array[v_filters ->> 'respondentId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."answers"::text ilike v_search)
        and (v_all or x."respondent_id" = auth.uid())
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'formId', x."form_id", 'versionId', x."version_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'respondentId', x."respondent_id", 'answers', x."answers", 'status', x."status", 'source', x."source", 'reviewedBy', x."reviewed_by", 'reviewedAt', x."reviewed_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'submittedAt', x."submitted_at", 'updatedAt', x."updated_at", 'score', x."score", 'maxScore', x."max_score", 'passed', x."passed") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."form_submissions" x
      where x."tenant_id" = page_form_submissions.tenant
        and (not (v_filters -> 'formId' is not null and jsonb_typeof(v_filters -> 'formId') <> 'null' and not (jsonb_typeof(v_filters -> 'formId') = 'array' and jsonb_array_length(v_filters -> 'formId') = 0)) or x."form_id" = any((case when jsonb_typeof(v_filters -> 'formId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'formId')) else array[v_filters ->> 'formId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'respondentId' is not null and jsonb_typeof(v_filters -> 'respondentId') <> 'null' and not (jsonb_typeof(v_filters -> 'respondentId') = 'array' and jsonb_array_length(v_filters -> 'respondentId') = 0)) or x."respondent_id" = any((case when jsonb_typeof(v_filters -> 'respondentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'respondentId')) else array[v_filters ->> 'respondentId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."answers"::text ilike v_search)
        and (v_all or x."respondent_id" = auth.uid())
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'formId', x."form_id", 'versionId', x."version_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'respondentId', x."respondent_id", 'answers', x."answers", 'status', x."status", 'source', x."source", 'reviewedBy', x."reviewed_by", 'reviewedAt', x."reviewed_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'submittedAt', x."submitted_at", 'updatedAt', x."updated_at", 'score', x."score", 'maxScore', x."max_score", 'passed', x."passed") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."form_submissions" x
      where x."tenant_id" = page_form_submissions.tenant
        and (not (v_filters -> 'formId' is not null and jsonb_typeof(v_filters -> 'formId') <> 'null' and not (jsonb_typeof(v_filters -> 'formId') = 'array' and jsonb_array_length(v_filters -> 'formId') = 0)) or x."form_id" = any((case when jsonb_typeof(v_filters -> 'formId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'formId')) else array[v_filters ->> 'formId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'respondentId' is not null and jsonb_typeof(v_filters -> 'respondentId') <> 'null' and not (jsonb_typeof(v_filters -> 'respondentId') = 'array' and jsonb_array_length(v_filters -> 'respondentId') = 0)) or x."respondent_id" = any((case when jsonb_typeof(v_filters -> 'respondentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'respondentId')) else array[v_filters ->> 'respondentId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."answers"::text ilike v_search)
        and (v_all or x."respondent_id" = auth.uid())
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'submittedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'formId', x."form_id", 'versionId', x."version_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'respondentId', x."respondent_id", 'answers', x."answers", 'status', x."status", 'source', x."source", 'reviewedBy', x."reviewed_by", 'reviewedAt', x."reviewed_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'submittedAt', x."submitted_at", 'updatedAt', x."updated_at", 'score', x."score", 'maxScore', x."max_score", 'passed', x."passed") as j, jsonb_build_array((coalesce(x."submitted_at", timestamptz '-infinity'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."form_submissions" x
      where x."tenant_id" = page_form_submissions.tenant
        and (not (v_filters -> 'formId' is not null and jsonb_typeof(v_filters -> 'formId') <> 'null' and not (jsonb_typeof(v_filters -> 'formId') = 'array' and jsonb_array_length(v_filters -> 'formId') = 0)) or x."form_id" = any((case when jsonb_typeof(v_filters -> 'formId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'formId')) else array[v_filters ->> 'formId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'respondentId' is not null and jsonb_typeof(v_filters -> 'respondentId') <> 'null' and not (jsonb_typeof(v_filters -> 'respondentId') = 'array' and jsonb_array_length(v_filters -> 'respondentId') = 0)) or x."respondent_id" = any((case when jsonb_typeof(v_filters -> 'respondentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'respondentId')) else array[v_filters ->> 'respondentId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."answers"::text ilike v_search)
        and (v_all or x."respondent_id" = auth.uid())
        and (v_after is null or (coalesce(x."submitted_at", timestamptz '-infinity') >= (v_after ->> 0)::timestamptz and ((coalesce(x."submitted_at", timestamptz '-infinity') > (v_after ->> 0)::timestamptz) or (coalesce(x."submitted_at", timestamptz '-infinity') = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."submitted_at", timestamptz '-infinity') asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'submittedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'formId', x."form_id", 'versionId', x."version_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'respondentId', x."respondent_id", 'answers', x."answers", 'status', x."status", 'source', x."source", 'reviewedBy', x."reviewed_by", 'reviewedAt', x."reviewed_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'submittedAt', x."submitted_at", 'updatedAt', x."updated_at", 'score', x."score", 'maxScore', x."max_score", 'passed', x."passed") as j, jsonb_build_array((coalesce(x."submitted_at", timestamptz '-infinity'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."form_submissions" x
      where x."tenant_id" = page_form_submissions.tenant
        and (not (v_filters -> 'formId' is not null and jsonb_typeof(v_filters -> 'formId') <> 'null' and not (jsonb_typeof(v_filters -> 'formId') = 'array' and jsonb_array_length(v_filters -> 'formId') = 0)) or x."form_id" = any((case when jsonb_typeof(v_filters -> 'formId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'formId')) else array[v_filters ->> 'formId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'respondentId' is not null and jsonb_typeof(v_filters -> 'respondentId') <> 'null' and not (jsonb_typeof(v_filters -> 'respondentId') = 'array' and jsonb_array_length(v_filters -> 'respondentId') = 0)) or x."respondent_id" = any((case when jsonb_typeof(v_filters -> 'respondentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'respondentId')) else array[v_filters ->> 'respondentId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."answers"::text ilike v_search)
        and (v_all or x."respondent_id" = auth.uid())
        and (v_after is null or (coalesce(x."submitted_at", timestamptz '-infinity'), x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."submitted_at", timestamptz '-infinity') desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."form_submissions" x
      where x."tenant_id" = page_form_submissions.tenant
        and (not (v_filters -> 'formId' is not null and jsonb_typeof(v_filters -> 'formId') <> 'null' and not (jsonb_typeof(v_filters -> 'formId') = 'array' and jsonb_array_length(v_filters -> 'formId') = 0)) or x."form_id" = any((case when jsonb_typeof(v_filters -> 'formId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'formId')) else array[v_filters ->> 'formId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'respondentId' is not null and jsonb_typeof(v_filters -> 'respondentId') <> 'null' and not (jsonb_typeof(v_filters -> 'respondentId') = 'array' and jsonb_array_length(v_filters -> 'respondentId') = 0)) or x."respondent_id" = any((case when jsonb_typeof(v_filters -> 'respondentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'respondentId')) else array[v_filters ->> 'respondentId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (v_search is null or x."answers"::text ilike v_search)
        and (v_all or x."respondent_id" = auth.uid())
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_inventory_levels (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_inventory_levels.filters, '{}'::jsonb);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'locationId') then
      raise exception 'facet is one of status, locationId' using errcode = '22023', hint = 'INVENTORY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end)::text when 'locationId' then (x."location_id"::text)::text end) as v
      from "better_supabase"."stock_levels" x
      where x."tenant_id" = page_inventory_levels.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x."variant_id"::text ilike v_search or x."location_id"::text ilike v_search)
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
      select 1 from "better_supabase"."stock_levels" x
      where x."tenant_id" = page_inventory_levels.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x."variant_id"::text ilike v_search or x."location_id"::text ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('available', 'onHand', 'variantId') then
    raise exception 'sort is one of available, onHand, variantId' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."variant_id"::text || ':' || x."location_id"::text,
      'variantId', x."variant_id",
      'locationId', x."location_id",
      'onHand', x."on_hand"::text,
      'allocated', x."reserved"::text,
      'available', x."available"::text,
      'incoming', x."incoming"::text,
      'reorderPoint', x."reorder_point"::text,
      'status', case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end) as j, jsonb_build_array((x."available")::text, ((x."variant_id"::text || ':' || x."location_id"::text))::text) as k
    from (
      select * from "better_supabase"."stock_levels" x
      where x."tenant_id" = page_inventory_levels.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x."variant_id"::text ilike v_search or x."location_id"::text ilike v_search)
        and (v_after is null or (x."available", (x."variant_id"::text || ':' || x."location_id"::text)) > ((v_after ->> 0)::numeric, (v_after ->> 1)::text))
      order by x."available" asc, (x."variant_id"::text || ':' || x."location_id"::text) asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."variant_id"::text || ':' || x."location_id"::text,
      'variantId', x."variant_id",
      'locationId', x."location_id",
      'onHand', x."on_hand"::text,
      'allocated', x."reserved"::text,
      'available', x."available"::text,
      'incoming', x."incoming"::text,
      'reorderPoint', x."reorder_point"::text,
      'status', case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end) as j, jsonb_build_array((x."available")::text, ((x."variant_id"::text || ':' || x."location_id"::text))::text) as k
    from (
      select * from "better_supabase"."stock_levels" x
      where x."tenant_id" = page_inventory_levels.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x."variant_id"::text ilike v_search or x."location_id"::text ilike v_search)
        and (v_after is null or (x."available" <= (v_after ->> 0)::numeric and ((x."available" < (v_after ->> 0)::numeric) or (x."available" = (v_after ->> 0)::numeric and (x."variant_id"::text || ':' || x."location_id"::text) > (v_after ->> 1)::text))))
      order by x."available" desc, (x."variant_id"::text || ':' || x."location_id"::text) asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'available' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."variant_id"::text || ':' || x."location_id"::text,
      'variantId', x."variant_id",
      'locationId', x."location_id",
      'onHand', x."on_hand"::text,
      'allocated', x."reserved"::text,
      'available', x."available"::text,
      'incoming', x."incoming"::text,
      'reorderPoint', x."reorder_point"::text,
      'status', case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end) as j, jsonb_build_array((x."available")::text, ((x."variant_id"::text || ':' || x."location_id"::text))::text) as k
    from (
      select * from "better_supabase"."stock_levels" x
      where x."tenant_id" = page_inventory_levels.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x."variant_id"::text ilike v_search or x."location_id"::text ilike v_search)
        and (v_after is null or (x."available", (x."variant_id"::text || ':' || x."location_id"::text)) > ((v_after ->> 0)::numeric, (v_after ->> 1)::text))
      order by x."available" asc, (x."variant_id"::text || ':' || x."location_id"::text) asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'available' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."variant_id"::text || ':' || x."location_id"::text,
      'variantId', x."variant_id",
      'locationId', x."location_id",
      'onHand', x."on_hand"::text,
      'allocated', x."reserved"::text,
      'available', x."available"::text,
      'incoming', x."incoming"::text,
      'reorderPoint', x."reorder_point"::text,
      'status', case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end) as j, jsonb_build_array((x."available")::text, ((x."variant_id"::text || ':' || x."location_id"::text))::text) as k
    from (
      select * from "better_supabase"."stock_levels" x
      where x."tenant_id" = page_inventory_levels.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x."variant_id"::text ilike v_search or x."location_id"::text ilike v_search)
        and (v_after is null or (x."available" <= (v_after ->> 0)::numeric and ((x."available" < (v_after ->> 0)::numeric) or (x."available" = (v_after ->> 0)::numeric and (x."variant_id"::text || ':' || x."location_id"::text) > (v_after ->> 1)::text))))
      order by x."available" desc, (x."variant_id"::text || ':' || x."location_id"::text) asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'onHand' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."variant_id"::text || ':' || x."location_id"::text,
      'variantId', x."variant_id",
      'locationId', x."location_id",
      'onHand', x."on_hand"::text,
      'allocated', x."reserved"::text,
      'available', x."available"::text,
      'incoming', x."incoming"::text,
      'reorderPoint', x."reorder_point"::text,
      'status', case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end) as j, jsonb_build_array((x."on_hand")::text, ((x."variant_id"::text || ':' || x."location_id"::text))::text) as k
    from (
      select * from "better_supabase"."stock_levels" x
      where x."tenant_id" = page_inventory_levels.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x."variant_id"::text ilike v_search or x."location_id"::text ilike v_search)
        and (v_after is null or (x."on_hand", (x."variant_id"::text || ':' || x."location_id"::text)) > ((v_after ->> 0)::numeric, (v_after ->> 1)::text))
      order by x."on_hand" asc, (x."variant_id"::text || ':' || x."location_id"::text) asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'onHand' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."variant_id"::text || ':' || x."location_id"::text,
      'variantId', x."variant_id",
      'locationId', x."location_id",
      'onHand', x."on_hand"::text,
      'allocated', x."reserved"::text,
      'available', x."available"::text,
      'incoming', x."incoming"::text,
      'reorderPoint', x."reorder_point"::text,
      'status', case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end) as j, jsonb_build_array((x."on_hand")::text, ((x."variant_id"::text || ':' || x."location_id"::text))::text) as k
    from (
      select * from "better_supabase"."stock_levels" x
      where x."tenant_id" = page_inventory_levels.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x."variant_id"::text ilike v_search or x."location_id"::text ilike v_search)
        and (v_after is null or (x."on_hand" <= (v_after ->> 0)::numeric and ((x."on_hand" < (v_after ->> 0)::numeric) or (x."on_hand" = (v_after ->> 0)::numeric and (x."variant_id"::text || ':' || x."location_id"::text) > (v_after ->> 1)::text))))
      order by x."on_hand" desc, (x."variant_id"::text || ':' || x."location_id"::text) asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'variantId' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."variant_id"::text || ':' || x."location_id"::text,
      'variantId', x."variant_id",
      'locationId', x."location_id",
      'onHand', x."on_hand"::text,
      'allocated', x."reserved"::text,
      'available', x."available"::text,
      'incoming', x."incoming"::text,
      'reorderPoint', x."reorder_point"::text,
      'status', case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end) as j, jsonb_build_array((x."variant_id"::text)::text, ((x."variant_id"::text || ':' || x."location_id"::text))::text) as k
    from (
      select * from "better_supabase"."stock_levels" x
      where x."tenant_id" = page_inventory_levels.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x."variant_id"::text ilike v_search or x."location_id"::text ilike v_search)
        and (v_after is null or (x."variant_id"::text, (x."variant_id"::text || ':' || x."location_id"::text)) > ((v_after ->> 0)::text, (v_after ->> 1)::text))
      order by x."variant_id"::text asc, (x."variant_id"::text || ':' || x."location_id"::text) asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'variantId' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."variant_id"::text || ':' || x."location_id"::text,
      'variantId', x."variant_id",
      'locationId', x."location_id",
      'onHand', x."on_hand"::text,
      'allocated', x."reserved"::text,
      'available', x."available"::text,
      'incoming', x."incoming"::text,
      'reorderPoint', x."reorder_point"::text,
      'status', case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end) as j, jsonb_build_array((x."variant_id"::text)::text, ((x."variant_id"::text || ':' || x."location_id"::text))::text) as k
    from (
      select * from "better_supabase"."stock_levels" x
      where x."tenant_id" = page_inventory_levels.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x."variant_id"::text ilike v_search or x."location_id"::text ilike v_search)
        and (v_after is null or (x."variant_id"::text <= (v_after ->> 0)::text and ((x."variant_id"::text < (v_after ->> 0)::text) or (x."variant_id"::text = (v_after ->> 0)::text and (x."variant_id"::text || ':' || x."location_id"::text) > (v_after ->> 1)::text))))
      order by x."variant_id"::text desc, (x."variant_id"::text || ':' || x."location_id"::text) asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."stock_levels" x
      where x."tenant_id" = page_inventory_levels.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or case when x."available" <= 0 then 'out' when x."reorder_point" is not null and x."available" <= x."reorder_point" then 'low' else 'in_stock' end = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."variant_id" = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x."variant_id"::text ilike v_search or x."location_id"::text ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_inventory_lots (
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
  v_filters jsonb := coalesce(page_inventory_lots.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_inventory_lots.tenant, 'inventory.read'), false)) then
    raise exception 'not allowed to read this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('expiry', 'locationId') then
      raise exception 'facet is one of expiry, locationId' using errcode = '22023', hint = 'INVENTORY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'expiry' then (case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end)::text when 'locationId' then (x."location_id"::text)::text end) as v
      from (select y.*, lo."id" as lot_pk, lo."code" as lot_code, lo."variant_id" as lot_variant, lo."expires_on" as lot_expires_on from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id" where y."on_hand" > 0) x
      where x."tenant_id" = page_inventory_lots.tenant
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x.lot_variant = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x.lot_code ilike v_search)
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
      select 1 from (select y.*, lo."id" as lot_pk, lo."code" as lot_code, lo."variant_id" as lot_variant, lo."expires_on" as lot_expires_on from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id" where y."on_hand" > 0) x
      where x."tenant_id" = page_inventory_lots.tenant
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x.lot_variant = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x.lot_code ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('expiresOn', 'onHand', 'code') then
    raise exception 'sort is one of expiresOn, onHand, code' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, ''), 'lotId', x.lot_pk, 'code', x.lot_code, 'variantId', x.lot_variant, 'locationId', x."location_id", 'binId', x."bin_id", 'expiresOn', x.lot_expires_on, 'onHand', x."on_hand"::text, 'expiry', case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end) as j, jsonb_build_array((coalesce(x.lot_expires_on, date '9999-12-31'))::text, ((x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')))::text) as k
    from (
      select * from (select y.*, lo."id" as lot_pk, lo."code" as lot_code, lo."variant_id" as lot_variant, lo."expires_on" as lot_expires_on from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id" where y."on_hand" > 0) x
      where x."tenant_id" = page_inventory_lots.tenant
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x.lot_variant = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x.lot_code ilike v_search)
        and (v_after is null or (coalesce(x.lot_expires_on, date '9999-12-31'), (x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, ''))) > ((v_after ->> 0)::date, (v_after ->> 1)::text))
      order by coalesce(x.lot_expires_on, date '9999-12-31') asc, (x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')) asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, ''), 'lotId', x.lot_pk, 'code', x.lot_code, 'variantId', x.lot_variant, 'locationId', x."location_id", 'binId', x."bin_id", 'expiresOn', x.lot_expires_on, 'onHand', x."on_hand"::text, 'expiry', case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end) as j, jsonb_build_array((coalesce(x.lot_expires_on, date '9999-12-31'))::text, ((x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')))::text) as k
    from (
      select * from (select y.*, lo."id" as lot_pk, lo."code" as lot_code, lo."variant_id" as lot_variant, lo."expires_on" as lot_expires_on from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id" where y."on_hand" > 0) x
      where x."tenant_id" = page_inventory_lots.tenant
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x.lot_variant = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x.lot_code ilike v_search)
        and (v_after is null or (coalesce(x.lot_expires_on, date '9999-12-31') <= (v_after ->> 0)::date and ((coalesce(x.lot_expires_on, date '9999-12-31') < (v_after ->> 0)::date) or (coalesce(x.lot_expires_on, date '9999-12-31') = (v_after ->> 0)::date and (x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')) > (v_after ->> 1)::text))))
      order by coalesce(x.lot_expires_on, date '9999-12-31') desc, (x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')) asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'expiresOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, ''), 'lotId', x.lot_pk, 'code', x.lot_code, 'variantId', x.lot_variant, 'locationId', x."location_id", 'binId', x."bin_id", 'expiresOn', x.lot_expires_on, 'onHand', x."on_hand"::text, 'expiry', case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end) as j, jsonb_build_array((coalesce(x.lot_expires_on, date '9999-12-31'))::text, ((x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')))::text) as k
    from (
      select * from (select y.*, lo."id" as lot_pk, lo."code" as lot_code, lo."variant_id" as lot_variant, lo."expires_on" as lot_expires_on from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id" where y."on_hand" > 0) x
      where x."tenant_id" = page_inventory_lots.tenant
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x.lot_variant = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x.lot_code ilike v_search)
        and (v_after is null or (coalesce(x.lot_expires_on, date '9999-12-31'), (x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, ''))) > ((v_after ->> 0)::date, (v_after ->> 1)::text))
      order by coalesce(x.lot_expires_on, date '9999-12-31') asc, (x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')) asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'expiresOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, ''), 'lotId', x.lot_pk, 'code', x.lot_code, 'variantId', x.lot_variant, 'locationId', x."location_id", 'binId', x."bin_id", 'expiresOn', x.lot_expires_on, 'onHand', x."on_hand"::text, 'expiry', case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end) as j, jsonb_build_array((coalesce(x.lot_expires_on, date '9999-12-31'))::text, ((x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')))::text) as k
    from (
      select * from (select y.*, lo."id" as lot_pk, lo."code" as lot_code, lo."variant_id" as lot_variant, lo."expires_on" as lot_expires_on from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id" where y."on_hand" > 0) x
      where x."tenant_id" = page_inventory_lots.tenant
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x.lot_variant = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x.lot_code ilike v_search)
        and (v_after is null or (coalesce(x.lot_expires_on, date '9999-12-31') <= (v_after ->> 0)::date and ((coalesce(x.lot_expires_on, date '9999-12-31') < (v_after ->> 0)::date) or (coalesce(x.lot_expires_on, date '9999-12-31') = (v_after ->> 0)::date and (x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')) > (v_after ->> 1)::text))))
      order by coalesce(x.lot_expires_on, date '9999-12-31') desc, (x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')) asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'onHand' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, ''), 'lotId', x.lot_pk, 'code', x.lot_code, 'variantId', x.lot_variant, 'locationId', x."location_id", 'binId', x."bin_id", 'expiresOn', x.lot_expires_on, 'onHand', x."on_hand"::text, 'expiry', case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end) as j, jsonb_build_array((x."on_hand")::text, ((x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')))::text) as k
    from (
      select * from (select y.*, lo."id" as lot_pk, lo."code" as lot_code, lo."variant_id" as lot_variant, lo."expires_on" as lot_expires_on from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id" where y."on_hand" > 0) x
      where x."tenant_id" = page_inventory_lots.tenant
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x.lot_variant = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x.lot_code ilike v_search)
        and (v_after is null or (x."on_hand", (x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, ''))) > ((v_after ->> 0)::numeric, (v_after ->> 1)::text))
      order by x."on_hand" asc, (x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')) asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'onHand' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, ''), 'lotId', x.lot_pk, 'code', x.lot_code, 'variantId', x.lot_variant, 'locationId', x."location_id", 'binId', x."bin_id", 'expiresOn', x.lot_expires_on, 'onHand', x."on_hand"::text, 'expiry', case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end) as j, jsonb_build_array((x."on_hand")::text, ((x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')))::text) as k
    from (
      select * from (select y.*, lo."id" as lot_pk, lo."code" as lot_code, lo."variant_id" as lot_variant, lo."expires_on" as lot_expires_on from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id" where y."on_hand" > 0) x
      where x."tenant_id" = page_inventory_lots.tenant
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x.lot_variant = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x.lot_code ilike v_search)
        and (v_after is null or (x."on_hand" <= (v_after ->> 0)::numeric and ((x."on_hand" < (v_after ->> 0)::numeric) or (x."on_hand" = (v_after ->> 0)::numeric and (x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')) > (v_after ->> 1)::text))))
      order by x."on_hand" desc, (x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')) asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'code' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, ''), 'lotId', x.lot_pk, 'code', x.lot_code, 'variantId', x.lot_variant, 'locationId', x."location_id", 'binId', x."bin_id", 'expiresOn', x.lot_expires_on, 'onHand', x."on_hand"::text, 'expiry', case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end) as j, jsonb_build_array((lower(x.lot_code))::text, ((x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')))::text) as k
    from (
      select * from (select y.*, lo."id" as lot_pk, lo."code" as lot_code, lo."variant_id" as lot_variant, lo."expires_on" as lot_expires_on from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id" where y."on_hand" > 0) x
      where x."tenant_id" = page_inventory_lots.tenant
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x.lot_variant = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x.lot_code ilike v_search)
        and (v_after is null or (lower(x.lot_code), (x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, ''))) > ((v_after ->> 0)::text, (v_after ->> 1)::text))
      order by lower(x.lot_code) asc, (x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')) asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'code' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, ''), 'lotId', x.lot_pk, 'code', x.lot_code, 'variantId', x.lot_variant, 'locationId', x."location_id", 'binId', x."bin_id", 'expiresOn', x.lot_expires_on, 'onHand', x."on_hand"::text, 'expiry', case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end) as j, jsonb_build_array((lower(x.lot_code))::text, ((x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')))::text) as k
    from (
      select * from (select y.*, lo."id" as lot_pk, lo."code" as lot_code, lo."variant_id" as lot_variant, lo."expires_on" as lot_expires_on from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id" where y."on_hand" > 0) x
      where x."tenant_id" = page_inventory_lots.tenant
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x.lot_variant = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x.lot_code ilike v_search)
        and (v_after is null or (lower(x.lot_code) <= (v_after ->> 0)::text and ((lower(x.lot_code) < (v_after ->> 0)::text) or (lower(x.lot_code) = (v_after ->> 0)::text and (x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')) > (v_after ->> 1)::text))))
      order by lower(x.lot_code) desc, (x.lot_pk::text || ':' || x."location_id"::text || ':' || coalesce(x."bin_id"::text, '')) asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from (select y.*, lo."id" as lot_pk, lo."code" as lot_code, lo."variant_id" as lot_variant, lo."expires_on" as lot_expires_on from "better_supabase"."stock_buckets" y join "better_supabase"."stock_lots" lo on lo."id" = y."lot_id" where y."on_hand" > 0) x
      where x."tenant_id" = page_inventory_lots.tenant
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x.lot_expires_on is null then 'none' when x.lot_expires_on < current_date then 'expired' when x.lot_expires_on <= current_date + 30 then 'soon' else 'later' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x.lot_variant = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::uuid[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."location_id" = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::uuid[]))
        and (v_search is null or x.lot_code ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_inventory_movements (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_inventory_movements.filters, '{}'::jsonb);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind', 'locationId') then
      raise exception 'facet is one of kind, locationId' using errcode = '22023', hint = 'INVENTORY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind")::text when 'locationId' then (x."metadata" ->> 'locationId')::text end) as v
      from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = page_inventory_movements.tenant
        and x."kind" like 'stock.%'
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."metadata" ->> 'variantId' = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."metadata" ->> 'locationId' = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or x."metadata" ->> 'binId' = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or x."metadata" ->> 'lotId' = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."reference_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."reference_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and (v_search is null or x."kind" ilike v_search or x."reference_id" ilike v_search)
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
      select 1 from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = page_inventory_movements.tenant
        and x."kind" like 'stock.%'
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."metadata" ->> 'variantId' = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."metadata" ->> 'locationId' = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or x."metadata" ->> 'binId' = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or x."metadata" ->> 'lotId' = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."reference_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."reference_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and (v_search is null or x."kind" ilike v_search or x."reference_id" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('effectiveAt', 'quantity') then
    raise exception 'sort is one of effectiveAt, quantity' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id",
      'kind', x."kind",
      'variantId', x."metadata" ->> 'variantId',
      'locationId', x."metadata" ->> 'locationId',
      'binId', x."metadata" ->> 'binId',
      'lotId', x."metadata" ->> 'lotId',
      'quantity', x."metadata" ->> 'quantity',
      'documentType', x."reference_type",
      'documentId', x."reference_id",
      'effectiveAt', x."effective_at") as j, jsonb_build_array((x."effective_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = page_inventory_movements.tenant
        and x."kind" like 'stock.%'
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."metadata" ->> 'variantId' = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."metadata" ->> 'locationId' = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or x."metadata" ->> 'binId' = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or x."metadata" ->> 'lotId' = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."reference_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."reference_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and (v_search is null or x."kind" ilike v_search or x."reference_id" ilike v_search)
        and (v_after is null or (x."effective_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."effective_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id",
      'kind', x."kind",
      'variantId', x."metadata" ->> 'variantId',
      'locationId', x."metadata" ->> 'locationId',
      'binId', x."metadata" ->> 'binId',
      'lotId', x."metadata" ->> 'lotId',
      'quantity', x."metadata" ->> 'quantity',
      'documentType', x."reference_type",
      'documentId', x."reference_id",
      'effectiveAt', x."effective_at") as j, jsonb_build_array((x."effective_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = page_inventory_movements.tenant
        and x."kind" like 'stock.%'
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."metadata" ->> 'variantId' = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."metadata" ->> 'locationId' = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or x."metadata" ->> 'binId' = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or x."metadata" ->> 'lotId' = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."reference_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."reference_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and (v_search is null or x."kind" ilike v_search or x."reference_id" ilike v_search)
        and (v_after is null or (x."effective_at" <= (v_after ->> 0)::timestamptz and ((x."effective_at" < (v_after ->> 0)::timestamptz) or (x."effective_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."effective_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'effectiveAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id",
      'kind', x."kind",
      'variantId', x."metadata" ->> 'variantId',
      'locationId', x."metadata" ->> 'locationId',
      'binId', x."metadata" ->> 'binId',
      'lotId', x."metadata" ->> 'lotId',
      'quantity', x."metadata" ->> 'quantity',
      'documentType', x."reference_type",
      'documentId', x."reference_id",
      'effectiveAt', x."effective_at") as j, jsonb_build_array((x."effective_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = page_inventory_movements.tenant
        and x."kind" like 'stock.%'
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."metadata" ->> 'variantId' = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."metadata" ->> 'locationId' = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or x."metadata" ->> 'binId' = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or x."metadata" ->> 'lotId' = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."reference_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."reference_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and (v_search is null or x."kind" ilike v_search or x."reference_id" ilike v_search)
        and (v_after is null or (x."effective_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."effective_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'effectiveAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id",
      'kind', x."kind",
      'variantId', x."metadata" ->> 'variantId',
      'locationId', x."metadata" ->> 'locationId',
      'binId', x."metadata" ->> 'binId',
      'lotId', x."metadata" ->> 'lotId',
      'quantity', x."metadata" ->> 'quantity',
      'documentType', x."reference_type",
      'documentId', x."reference_id",
      'effectiveAt', x."effective_at") as j, jsonb_build_array((x."effective_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = page_inventory_movements.tenant
        and x."kind" like 'stock.%'
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."metadata" ->> 'variantId' = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."metadata" ->> 'locationId' = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or x."metadata" ->> 'binId' = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or x."metadata" ->> 'lotId' = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."reference_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."reference_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and (v_search is null or x."kind" ilike v_search or x."reference_id" ilike v_search)
        and (v_after is null or (x."effective_at" <= (v_after ->> 0)::timestamptz and ((x."effective_at" < (v_after ->> 0)::timestamptz) or (x."effective_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."effective_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'quantity' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id",
      'kind', x."kind",
      'variantId', x."metadata" ->> 'variantId',
      'locationId', x."metadata" ->> 'locationId',
      'binId', x."metadata" ->> 'binId',
      'lotId', x."metadata" ->> 'lotId',
      'quantity', x."metadata" ->> 'quantity',
      'documentType', x."reference_type",
      'documentId', x."reference_id",
      'effectiveAt', x."effective_at") as j, jsonb_build_array((abs(coalesce((x."metadata" ->> 'quantity')::numeric, 0)))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = page_inventory_movements.tenant
        and x."kind" like 'stock.%'
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."metadata" ->> 'variantId' = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."metadata" ->> 'locationId' = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or x."metadata" ->> 'binId' = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or x."metadata" ->> 'lotId' = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."reference_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."reference_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and (v_search is null or x."kind" ilike v_search or x."reference_id" ilike v_search)
        and (v_after is null or (abs(coalesce((x."metadata" ->> 'quantity')::numeric, 0)), x."id") > ((v_after ->> 0)::numeric, (v_after ->> 1)::uuid))
      order by abs(coalesce((x."metadata" ->> 'quantity')::numeric, 0)) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'quantity' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVENTORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
      'id', x."id",
      'kind', x."kind",
      'variantId', x."metadata" ->> 'variantId',
      'locationId', x."metadata" ->> 'locationId',
      'binId', x."metadata" ->> 'binId',
      'lotId', x."metadata" ->> 'lotId',
      'quantity', x."metadata" ->> 'quantity',
      'documentType', x."reference_type",
      'documentId', x."reference_id",
      'effectiveAt', x."effective_at") as j, jsonb_build_array((abs(coalesce((x."metadata" ->> 'quantity')::numeric, 0)))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = page_inventory_movements.tenant
        and x."kind" like 'stock.%'
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."metadata" ->> 'variantId' = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."metadata" ->> 'locationId' = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or x."metadata" ->> 'binId' = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or x."metadata" ->> 'lotId' = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."reference_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."reference_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and (v_search is null or x."kind" ilike v_search or x."reference_id" ilike v_search)
        and (v_after is null or (abs(coalesce((x."metadata" ->> 'quantity')::numeric, 0)) <= (v_after ->> 0)::numeric and ((abs(coalesce((x."metadata" ->> 'quantity')::numeric, 0)) < (v_after ->> 0)::numeric) or (abs(coalesce((x."metadata" ->> 'quantity')::numeric, 0)) = (v_after ->> 0)::numeric and x."id" > (v_after ->> 1)::uuid))))
      order by abs(coalesce((x."metadata" ->> 'quantity')::numeric, 0)) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = page_inventory_movements.tenant
        and x."kind" like 'stock.%'
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or x."metadata" ->> 'variantId' = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or x."metadata" ->> 'locationId' = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or x."metadata" ->> 'binId' = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or x."metadata" ->> 'lotId' = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or x."reference_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or x."reference_id" = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and (v_search is null or x."kind" ilike v_search or x."reference_id" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_qualification_types (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_qualification_types.filters, '{}'::jsonb);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('state', 'expiry') then
      raise exception 'facet is one of state, expiry' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'state' then (case when x."archived_at" is null then 'active' else 'archived' end)::text when 'expiry' then (case when x."valid_for_months" is null then 'never' else 'expires' end)::text end) as v
      from "better_supabase"."qualification_types" x
      where x."tenant_id" = page_qualification_types.tenant
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or case when x."archived_at" is null then 'active' else 'archived' end = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x."valid_for_months" is null then 'never' else 'expires' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
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
      select 1 from "better_supabase"."qualification_types" x
      where x."tenant_id" = page_qualification_types.tenant
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or case when x."archived_at" is null then 'active' else 'archived' end = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x."valid_for_months" is null then 'never' else 'expires' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'key') then
    raise exception 'sort is one of name, key' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'holderTypes', to_jsonb(x."holder_types"), 'validForMonths', x."valid_for_months", 'evidenceRequired', x."evidence_required", 'courseId', x."course_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."qualification_types" x
      where x."tenant_id" = page_qualification_types.tenant
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or case when x."archived_at" is null then 'active' else 'archived' end = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x."valid_for_months" is null then 'never' else 'expires' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'holderTypes', to_jsonb(x."holder_types"), 'validForMonths', x."valid_for_months", 'evidenceRequired', x."evidence_required", 'courseId', x."course_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."qualification_types" x
      where x."tenant_id" = page_qualification_types.tenant
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or case when x."archived_at" is null then 'active' else 'archived' end = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x."valid_for_months" is null then 'never' else 'expires' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'holderTypes', to_jsonb(x."holder_types"), 'validForMonths', x."valid_for_months", 'evidenceRequired', x."evidence_required", 'courseId', x."course_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."qualification_types" x
      where x."tenant_id" = page_qualification_types.tenant
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or case when x."archived_at" is null then 'active' else 'archived' end = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x."valid_for_months" is null then 'never' else 'expires' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'holderTypes', to_jsonb(x."holder_types"), 'validForMonths', x."valid_for_months", 'evidenceRequired', x."evidence_required", 'courseId', x."course_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."qualification_types" x
      where x."tenant_id" = page_qualification_types.tenant
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or case when x."archived_at" is null then 'active' else 'archived' end = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x."valid_for_months" is null then 'never' else 'expires' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'holderTypes', to_jsonb(x."holder_types"), 'validForMonths', x."valid_for_months", 'evidenceRequired', x."evidence_required", 'courseId', x."course_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."key"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."qualification_types" x
      where x."tenant_id" = page_qualification_types.tenant
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or case when x."archived_at" is null then 'active' else 'archived' end = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x."valid_for_months" is null then 'never' else 'expires' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."key"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."key") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'QUALIFICATION_TYPE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'holderTypes', to_jsonb(x."holder_types"), 'validForMonths', x."valid_for_months", 'evidenceRequired', x."evidence_required", 'courseId', x."course_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."key"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."qualification_types" x
      where x."tenant_id" = page_qualification_types.tenant
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or case when x."archived_at" is null then 'active' else 'archived' end = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x."valid_for_months" is null then 'never' else 'expires' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."key") <= (v_after ->> 0)::text and ((lower(x."key") < (v_after ->> 0)::text) or (lower(x."key") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."key") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."qualification_types" x
      where x."tenant_id" = page_qualification_types.tenant
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or case when x."archived_at" is null then 'active' else 'archived' end = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'expiry' is not null and jsonb_typeof(v_filters -> 'expiry') <> 'null' and not (jsonb_typeof(v_filters -> 'expiry') = 'array' and jsonb_array_length(v_filters -> 'expiry') = 0)) or case when x."valid_for_months" is null then 'never' else 'expires' end = any((case when jsonb_typeof(v_filters -> 'expiry') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'expiry')) else array[v_filters ->> 'expiry'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_signature_requests (
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
  v_filters jsonb := coalesce(page_signature_requests.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false) or coalesce(better_supabase.can('tenant', page_signature_requests.tenant, 'signatures.read'), false)) then
    raise exception 'not allowed to list signature requests' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SIGNATURE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'SIGNATURE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."signature_requests" x
      where x."tenant_id" = page_signature_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false) or auth.uid() = any (x."signers"))
        and (v_search is null or x."subject_id" ilike v_search or x."message" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or auth.uid() = any (x."signers") or (coalesce(better_supabase.can('tenant', x."tenant_id", 'signatures.read'), false) and case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'warranty.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (x."subject_id")::uuid and s."id" = x."tenant_id")
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end))
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
      select 1 from "better_supabase"."signature_requests" x
      where x."tenant_id" = page_signature_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false) or auth.uid() = any (x."signers"))
        and (v_search is null or x."subject_id" ilike v_search or x."message" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or auth.uid() = any (x."signers") or (coalesce(better_supabase.can('tenant', x."tenant_id", 'signatures.read'), false) and case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'warranty.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (x."subject_id")::uuid and s."id" = x."tenant_id")
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'completedAt') then
    raise exception 'sort is one of createdAt, completedAt' using errcode = '22023', hint = 'SIGNATURE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SIGNATURE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SIGNATURE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'versionId', x."version_id", 'contentHash', x."content_hash", 'signers', to_jsonb(x."signers"), 'order', x."sign_order", 'status', x."status", 'approvalRequestId', x."approval_request_id", 'message', x."message", 'meaning', x."meaning", 'requestedBy', x."requested_by", 'createdAt', x."created_at", 'completedAt', x."completed_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."signature_requests" x
      where x."tenant_id" = page_signature_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false) or auth.uid() = any (x."signers"))
        and (v_search is null or x."subject_id" ilike v_search or x."message" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or auth.uid() = any (x."signers") or (coalesce(better_supabase.can('tenant', x."tenant_id", 'signatures.read'), false) and case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'warranty.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (x."subject_id")::uuid and s."id" = x."tenant_id")
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SIGNATURE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'versionId', x."version_id", 'contentHash', x."content_hash", 'signers', to_jsonb(x."signers"), 'order', x."sign_order", 'status', x."status", 'approvalRequestId', x."approval_request_id", 'message', x."message", 'meaning', x."meaning", 'requestedBy', x."requested_by", 'createdAt', x."created_at", 'completedAt', x."completed_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."signature_requests" x
      where x."tenant_id" = page_signature_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false) or auth.uid() = any (x."signers"))
        and (v_search is null or x."subject_id" ilike v_search or x."message" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or auth.uid() = any (x."signers") or (coalesce(better_supabase.can('tenant', x."tenant_id", 'signatures.read'), false) and case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'warranty.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (x."subject_id")::uuid and s."id" = x."tenant_id")
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SIGNATURE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'versionId', x."version_id", 'contentHash', x."content_hash", 'signers', to_jsonb(x."signers"), 'order', x."sign_order", 'status', x."status", 'approvalRequestId', x."approval_request_id", 'message', x."message", 'meaning', x."meaning", 'requestedBy', x."requested_by", 'createdAt', x."created_at", 'completedAt', x."completed_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."signature_requests" x
      where x."tenant_id" = page_signature_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false) or auth.uid() = any (x."signers"))
        and (v_search is null or x."subject_id" ilike v_search or x."message" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or auth.uid() = any (x."signers") or (coalesce(better_supabase.can('tenant', x."tenant_id", 'signatures.read'), false) and case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'warranty.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (x."subject_id")::uuid and s."id" = x."tenant_id")
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SIGNATURE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'versionId', x."version_id", 'contentHash', x."content_hash", 'signers', to_jsonb(x."signers"), 'order', x."sign_order", 'status', x."status", 'approvalRequestId', x."approval_request_id", 'message', x."message", 'meaning', x."meaning", 'requestedBy', x."requested_by", 'createdAt', x."created_at", 'completedAt', x."completed_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."signature_requests" x
      where x."tenant_id" = page_signature_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false) or auth.uid() = any (x."signers"))
        and (v_search is null or x."subject_id" ilike v_search or x."message" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or auth.uid() = any (x."signers") or (coalesce(better_supabase.can('tenant', x."tenant_id", 'signatures.read'), false) and case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'warranty.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (x."subject_id")::uuid and s."id" = x."tenant_id")
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'completedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SIGNATURE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'versionId', x."version_id", 'contentHash', x."content_hash", 'signers', to_jsonb(x."signers"), 'order', x."sign_order", 'status', x."status", 'approvalRequestId', x."approval_request_id", 'message', x."message", 'meaning', x."meaning", 'requestedBy', x."requested_by", 'createdAt', x."created_at", 'completedAt', x."completed_at") as j, jsonb_build_array((coalesce(x."completed_at", timestamptz '-infinity'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."signature_requests" x
      where x."tenant_id" = page_signature_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false) or auth.uid() = any (x."signers"))
        and (v_search is null or x."subject_id" ilike v_search or x."message" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or auth.uid() = any (x."signers") or (coalesce(better_supabase.can('tenant', x."tenant_id", 'signatures.read'), false) and case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'warranty.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (x."subject_id")::uuid and s."id" = x."tenant_id")
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end))
        and (v_after is null or (coalesce(x."completed_at", timestamptz '-infinity'), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."completed_at", timestamptz '-infinity') asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'completedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SIGNATURE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'versionId', x."version_id", 'contentHash', x."content_hash", 'signers', to_jsonb(x."signers"), 'order', x."sign_order", 'status', x."status", 'approvalRequestId', x."approval_request_id", 'message', x."message", 'meaning', x."meaning", 'requestedBy', x."requested_by", 'createdAt', x."created_at", 'completedAt', x."completed_at") as j, jsonb_build_array((coalesce(x."completed_at", timestamptz '-infinity'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."signature_requests" x
      where x."tenant_id" = page_signature_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false) or auth.uid() = any (x."signers"))
        and (v_search is null or x."subject_id" ilike v_search or x."message" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or auth.uid() = any (x."signers") or (coalesce(better_supabase.can('tenant', x."tenant_id", 'signatures.read'), false) and case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'warranty.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (x."subject_id")::uuid and s."id" = x."tenant_id")
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end))
        and (v_after is null or (coalesce(x."completed_at", timestamptz '-infinity') <= (v_after ->> 0)::timestamptz and ((coalesce(x."completed_at", timestamptz '-infinity') < (v_after ->> 0)::timestamptz) or (coalesce(x."completed_at", timestamptz '-infinity') = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."completed_at", timestamptz '-infinity') desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."signature_requests" x
      where x."tenant_id" = page_signature_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false) or auth.uid() = any (x."signers"))
        and (v_search is null or x."subject_id" ilike v_search or x."message" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or auth.uid() = any (x."signers") or (coalesce(better_supabase.can('tenant', x."tenant_id", 'signatures.read'), false) and case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'warranty.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (x."subject_id")::uuid and s."id" = x."tenant_id")
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_templates (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_templates.filters, '{}'::jsonb);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('type', 'language', 'scope') then
      raise exception 'facet is one of type, language, scope' using errcode = '22023', hint = 'TEMPLATE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'type' then (x."type")::text when 'language' then (x."language")::text when 'scope' then (x."scope")::text end) as v
      from "better_supabase"."templates" x
      where (x."scope" = 'system' or x."tenant_id" = page_templates.tenant or (x."scope" = 'brand' and x."brand" = "better_supabase"."template_brand"(page_templates.tenant)))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
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
      select 1 from "better_supabase"."templates" x
      where (x."scope" = 'system' or x."tenant_id" = page_templates.tenant or (x."scope" = 'brand' and x."brand" = "better_supabase"."template_brand"(page_templates.tenant)))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt', 'updatedAt') then
    raise exception 'sort is one of name, createdAt, updatedAt' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'brand', x."brand",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."templates" x
      where (x."scope" = 'system' or x."tenant_id" = page_templates.tenant or (x."scope" = 'brand' and x."brand" = "better_supabase"."template_brand"(page_templates.tenant)))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'brand', x."brand",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."templates" x
      where (x."scope" = 'system' or x."tenant_id" = page_templates.tenant or (x."scope" = 'brand' and x."brand" = "better_supabase"."template_brand"(page_templates.tenant)))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'brand', x."brand",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."templates" x
      where (x."scope" = 'system' or x."tenant_id" = page_templates.tenant or (x."scope" = 'brand' and x."brand" = "better_supabase"."template_brand"(page_templates.tenant)))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'brand', x."brand",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."templates" x
      where (x."scope" = 'system' or x."tenant_id" = page_templates.tenant or (x."scope" = 'brand' and x."brand" = "better_supabase"."template_brand"(page_templates.tenant)))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'brand', x."brand",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."templates" x
      where (x."scope" = 'system' or x."tenant_id" = page_templates.tenant or (x."scope" = 'brand' and x."brand" = "better_supabase"."template_brand"(page_templates.tenant)))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'brand', x."brand",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."templates" x
      where (x."scope" = 'system' or x."tenant_id" = page_templates.tenant or (x."scope" = 'brand' and x."brand" = "better_supabase"."template_brand"(page_templates.tenant)))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'brand', x."brand",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."templates" x
      where (x."scope" = 'system' or x."tenant_id" = page_templates.tenant or (x."scope" = 'brand' and x."brand" = "better_supabase"."template_brand"(page_templates.tenant)))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEMPLATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'brand', x."brand",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."templates" x
      where (x."scope" = 'system' or x."tenant_id" = page_templates.tenant or (x."scope" = 'brand' and x."brand" = "better_supabase"."template_brand"(page_templates.tenant)))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
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
      select 1 from "better_supabase"."templates" x
      where (x."scope" = 'system' or x."tenant_id" = page_templates.tenant or (x."scope" = 'brand' and x."brand" = "better_supabase"."template_brand"(page_templates.tenant)))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or x."type" = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'isDefault' is not null and jsonb_typeof(v_filters -> 'isDefault') <> 'null' and not (jsonb_typeof(v_filters -> 'isDefault') = 'array' and jsonb_array_length(v_filters -> 'isDefault') = 0)) or x."is_default"::text = any((case when jsonb_typeof(v_filters -> 'isDefault') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'isDefault')) else array[v_filters ->> 'isDefault'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_versions (
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
  v_filters jsonb := coalesce(page_versions.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_versions.tenant, 'versions.read'), false)) then
    raise exception 'not allowed to read these versions' using errcode = '42501', hint = 'VERSION_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'VERSION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('source', 'subjectType') then
      raise exception 'facet is one of source, subjectType' using errcode = '22023', hint = 'VERSION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'source' then (x."source")::text when 'subjectType' then (x."subject_type")::text end) as v
      from "better_supabase"."versions" x
      where x."tenant_id" = page_versions.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source" = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (v_search is null or x."label" ilike v_search or x."subject_id" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case x."subject_type"
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    else false
  end and x."subject_type" <> 'ai_document'))
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
      select 1 from "better_supabase"."versions" x
      where x."tenant_id" = page_versions.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source" = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (v_search is null or x."label" ilike v_search or x."subject_id" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case x."subject_type"
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    else false
  end and x."subject_type" <> 'ai_document'))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'number') then
    raise exception 'sort is one of createdAt, number' using errcode = '22023', hint = 'VERSION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'VERSION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'VERSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'number', x."number", 'label', x."label", 'source', x."source", 'frozen', x."frozen", 'contentHash', x."content_hash", 'storagePath', x."storage_path", 'fileSha256', x."file_hash", 'hashVersion', x."hash_version", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."versions" x
      where x."tenant_id" = page_versions.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source" = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (v_search is null or x."label" ilike v_search or x."subject_id" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case x."subject_type"
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    else false
  end and x."subject_type" <> 'ai_document'))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'VERSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'number', x."number", 'label', x."label", 'source', x."source", 'frozen', x."frozen", 'contentHash', x."content_hash", 'storagePath', x."storage_path", 'fileSha256', x."file_hash", 'hashVersion', x."hash_version", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."versions" x
      where x."tenant_id" = page_versions.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source" = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (v_search is null or x."label" ilike v_search or x."subject_id" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case x."subject_type"
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    else false
  end and x."subject_type" <> 'ai_document'))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'VERSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'number', x."number", 'label', x."label", 'source', x."source", 'frozen', x."frozen", 'contentHash', x."content_hash", 'storagePath', x."storage_path", 'fileSha256', x."file_hash", 'hashVersion', x."hash_version", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."versions" x
      where x."tenant_id" = page_versions.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source" = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (v_search is null or x."label" ilike v_search or x."subject_id" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case x."subject_type"
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    else false
  end and x."subject_type" <> 'ai_document'))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'VERSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'number', x."number", 'label', x."label", 'source', x."source", 'frozen', x."frozen", 'contentHash', x."content_hash", 'storagePath', x."storage_path", 'fileSha256', x."file_hash", 'hashVersion', x."hash_version", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."versions" x
      where x."tenant_id" = page_versions.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source" = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (v_search is null or x."label" ilike v_search or x."subject_id" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case x."subject_type"
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    else false
  end and x."subject_type" <> 'ai_document'))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'VERSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'number', x."number", 'label', x."label", 'source', x."source", 'frozen', x."frozen", 'contentHash', x."content_hash", 'storagePath', x."storage_path", 'fileSha256', x."file_hash", 'hashVersion', x."hash_version", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."number")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."versions" x
      where x."tenant_id" = page_versions.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source" = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (v_search is null or x."label" ilike v_search or x."subject_id" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case x."subject_type"
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    else false
  end and x."subject_type" <> 'ai_document'))
        and (v_after is null or (x."number" >= (v_after ->> 0)::integer and ((x."number" > (v_after ->> 0)::integer) or (x."number" = (v_after ->> 0)::integer and x."created_at" < (v_after ->> 1)::timestamptz) or (x."number" = (v_after ->> 0)::integer and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."number" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'number' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'VERSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'number', x."number", 'label', x."label", 'source', x."source", 'frozen', x."frozen", 'contentHash', x."content_hash", 'storagePath', x."storage_path", 'fileSha256', x."file_hash", 'hashVersion', x."hash_version", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."number")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."versions" x
      where x."tenant_id" = page_versions.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source" = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (v_search is null or x."label" ilike v_search or x."subject_id" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case x."subject_type"
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    else false
  end and x."subject_type" <> 'ai_document'))
        and (v_after is null or (x."number" <= (v_after ->> 0)::integer and ((x."number" < (v_after ->> 0)::integer) or (x."number" = (v_after ->> 0)::integer and x."created_at" < (v_after ->> 1)::timestamptz) or (x."number" = (v_after ->> 0)::integer and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."number" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."versions" x
      where x."tenant_id" = page_versions.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source" = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (v_search is null or x."label" ilike v_search or x."subject_id" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case x."subject_type"
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    else false
  end and x."subject_type" <> 'ai_document'))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_refresh (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_title text;
  v_body text;
  v_url text;
  v_facets jsonb;
  v_found boolean := false;
  v_hash text;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  case search_refresh.subject_type
    when 'message' then
      select s."tenant_id", s."body"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."messages" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'conversation' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."conversations" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'channel' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."topic"::text, s."purpose"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."channels" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'company' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."domain"::text, s."website"::text), ''), '/crm/contacts/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."companies" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'person' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."phone"::text, s."title"::text), ''), '/crm/contacts/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."people" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'deal' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."note"::text), ''), '/crm/deals', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."deals" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'course' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."courses" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'post' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."posts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'activity' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text, s."outcome"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."activities" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'quote' then
      select s."tenant_id", s."title"::text, null, '/crm/quotes/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."quotes" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_item' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."body"::text), ''), '/work', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."work_items" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'employee' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."job_title"::text), ''), '/people/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."employees" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'ledger_account' then
      select s."tenant_id", s."name"::text, null, '/finance', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."ledger_accounts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'invoice' then
      select s."tenant_id", s."title"::text, null, '/finance/payables', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."invoices" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."slug"::text), ''), '/shop', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."products" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product_variant' then
      select s."tenant_id", s."sku"::text, nullif(concat_ws(E'\n', s."title"::text, s."barcode"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."product_variants" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'rfq' then
      select s."tenant_id", s."title"::text, null, '/rfqs', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."rfqs" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'till' then
      select s."tenant_id", s."name"::text, null, '/tills', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."tills" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'order' then
      select s."tenant_id", s."number"::text, null, '/shop/orders/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'calendar_event' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."location"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."calendar_events" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'booking' then
      select s."tenant_id", s."customer_name"::text, null, '/calendar', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."bookings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'asset' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."assets" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'asset_location' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."asset_locations" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'lease' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."leases" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'expense_report' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."expense_reports" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'expense_line' then
      select s."tenant_id", s."description"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."expense_lines" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'donation_fund' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."donation_funds" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'warranty_claim' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."manufacturer"::text, s."decision"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."warranty_claims" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_order' then
      select s."tenant_id", s."title"::text, null, '/field/dispatch', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."work_orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'shipment' then
      select s."tenant_id", s."reference"::text, null, '/field/shipments', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."shipments" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'contract' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."contracts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'control' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."controls" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'compliance_policy' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."compliance_policies" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'qualification_type' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."name"::text, s."key"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."qualification_types" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'risk' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."cause"::text, s."consequence"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."risks" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'case' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."root_cause"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."cases" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'inspection' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."scope"::text, s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."inspections" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'inspection_program' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."inspection_programs" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'inspection_finding' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."inspection_findings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'form' then
      select s."tenant_id", s."title"::text, null, '/forms/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."forms" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'meeting' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."location"::text, s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."meetings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'meeting_decision' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."meeting_decisions" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'maintenance_plan' then
      select s."tenant_id", s."title"::text, null, '/maintenance', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."maintenance_plans" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'dam_usage_right' then
      select s."tenant_id", s."licensee"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."dam_usage_rights" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'lims_sample' then
      select s."tenant_id", s."title"::text, null, '/lims', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."lims_samples" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'tax_code' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."tax_codes" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'production_order' then
      select s."tenant_id", s."number"::text, nullif(concat_ws(E'\n', s."note"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."production_orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_center' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."work_centers" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'bank_account' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."bank_accounts" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'care_plan' then
      select s."tenant_id", s."title"::text, null, '/care-plans', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."care_plans" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'incident' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."incidents" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'advisory' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."tracking_id"::text, s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."advisories" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'advisory_product' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."advisory_products" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'vulnerability' then
      select s."tenant_id", s."vuln_id"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."vulnerabilities" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'content_entry' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."content_entries" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'document' then
      select s."tenant_id", s."name"::text, null, '/documents/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."documents" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'customer' then
      select s."organization_id", s."name"::text, null, '/customers/' || s."id"::text, jsonb_strip_nulls(jsonb_build_object('status', s."status"))
        into v_tenant, v_title, v_body, v_url, v_facets
        from "public"."customers" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'drive_node' then
      select s."tenant_id", f."name"::text, nullif(concat_ws(E'\n', f."content"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."drive_nodes" s
        join "better_supabase"."drive_node_search" f on f."id" = s."id"
        where s."id" = (search_refresh.subject_id)::uuid
        and f."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'project' then
      select s."organization_id", s."name"::text, null, '/projects/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "public"."projects" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."deleted_at" is null;
      v_found := found;
    when 'task' then
      select s."organization_id", s."title"::text, null, '/projects/' || s."project_id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "public"."tasks" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    else
      raise exception 'this subject type has no search entry in config.recordTypes' using errcode = '22023', hint = 'SEARCH_SUBJECT_UNKNOWN';
  end case;
  if not v_found then
    delete from "better_supabase"."search_documents"
    where "subject_type" = search_refresh.subject_type and "subject_id" = search_refresh.subject_id;
    return false;
  end if;
  v_hash := md5(coalesce(v_title, '') || E'\x1f' || coalesce(v_body, ''));
  insert into "better_supabase"."search_documents" ("tenant_id", "subject_type", "subject_id", "title", "title_search", "body", "url", "tsv", "content_hash", "updated_at", "facets", "sort_key")
  values (
    v_tenant, search_refresh.subject_type, search_refresh.subject_id, v_title, "better_supabase"."search_normalize"(v_title), v_body, v_url,
    setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_title)), 'A')
      || setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_body)), 'B'),
    v_hash, now(), v_facets, left("better_supabase"."search_normalize"(v_title), 200)
  )
  on conflict ("subject_type", "subject_id") do update set
    "tenant_id" = excluded."tenant_id",
    "title" = excluded."title",
    "title_search" = excluded."title_search",
    "body" = excluded."body",
    "url" = excluded."url",
    "tsv" = excluded."tsv",
    "content_hash" = excluded."content_hash",
    "facets" = excluded."facets",
    "sort_key" = excluded."sort_key",
    "updated_at" = now()
  where ("better_supabase"."search_documents"."tenant_id", "better_supabase"."search_documents"."title", "better_supabase"."search_documents"."body", "better_supabase"."search_documents"."url", "better_supabase"."search_documents"."facets")
    is distinct from (excluded."tenant_id", excluded."title", excluded."body", excluded."url", excluded."facets");
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  return true;
end;
$function$;

CREATE TRIGGER bsb_search_qualification_type_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, name, key ON better_supabase.qualification_types
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('qualification_type', 'id');

REVOKE ALL ON FUNCTION "api"."get_inventory_level"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_inventory_level"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_inventory_lot"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_inventory_lot"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_inventory_movement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_inventory_movement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_qualification_type"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_qualification_type"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_attachments"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_attachments"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_drive_documents"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_drive_documents"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_form_submissions"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_form_submissions"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_inventory_levels"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_inventory_levels"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_inventory_lots"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_inventory_lots"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_inventory_movements"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_inventory_movements"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_qualification_types"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_qualification_types"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_signature_requests"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_signature_requests"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_templates"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_templates"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_versions"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_versions"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_inventory_level"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_inventory_level"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_inventory_lot"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_inventory_lot"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_inventory_movement"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_inventory_movement"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_qualification_type"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_qualification_type"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_attachments"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_attachments"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_drive_documents"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_drive_documents"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_form_submissions"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_form_submissions"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_inventory_levels"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_inventory_levels"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_inventory_lots"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_inventory_lots"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_inventory_movements"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_inventory_movements"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_qualification_types"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_qualification_types"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_signature_requests"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_signature_requests"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_templates"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_templates"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_versions"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_versions"(uuid, jsonb) TO "authenticated", "service_role";
