SET local check_function_bodies = off;

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
      'productId', (select v."product_id" from "better_supabase"."product_variants" v where v."id" = (x."metadata" ->> 'variantId')::uuid),
      'locationId', x."metadata" ->> 'locationId',
      'binId', x."metadata" ->> 'binId',
      'lotId', x."metadata" ->> 'lotId',
      'quantity', x."metadata" ->> 'quantity',
      'unit', x."metadata" ->> 'unit',
      'reason', x."metadata" ->> 'reason',
      'note', x."memo",
      'actorId', x."actor_id",
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
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or (x."metadata" ->> 'variantId')::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (x."metadata" ->> 'variantId')::uuid in (select v."id" from "better_supabase"."product_variants" v where (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (v."product_id")::text = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::text[]))))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or (x."metadata" ->> 'locationId')::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or (x."metadata" ->> 'binId')::text = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or (x."metadata" ->> 'lotId')::text = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or (x."reference_type")::text = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or (x."reference_id")::text = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
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
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or (x."metadata" ->> 'variantId')::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (x."metadata" ->> 'variantId')::uuid in (select v."id" from "better_supabase"."product_variants" v where (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (v."product_id")::text = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::text[]))))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or (x."metadata" ->> 'locationId')::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or (x."metadata" ->> 'binId')::text = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or (x."metadata" ->> 'lotId')::text = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or (x."reference_type")::text = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or (x."reference_id")::text = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
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
      'productId', (select v."product_id" from "better_supabase"."product_variants" v where v."id" = (x."metadata" ->> 'variantId')::uuid),
      'locationId', x."metadata" ->> 'locationId',
      'binId', x."metadata" ->> 'binId',
      'lotId', x."metadata" ->> 'lotId',
      'quantity', x."metadata" ->> 'quantity',
      'unit', x."metadata" ->> 'unit',
      'reason', x."metadata" ->> 'reason',
      'note', x."memo",
      'actorId', x."actor_id",
      'documentType', x."reference_type",
      'documentId', x."reference_id",
      'effectiveAt', x."effective_at") as j, jsonb_build_array((x."effective_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = page_inventory_movements.tenant
        and x."kind" like 'stock.%'
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or (x."metadata" ->> 'variantId')::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (x."metadata" ->> 'variantId')::uuid in (select v."id" from "better_supabase"."product_variants" v where (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (v."product_id")::text = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::text[]))))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or (x."metadata" ->> 'locationId')::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or (x."metadata" ->> 'binId')::text = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or (x."metadata" ->> 'lotId')::text = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or (x."reference_type")::text = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or (x."reference_id")::text = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
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
      'productId', (select v."product_id" from "better_supabase"."product_variants" v where v."id" = (x."metadata" ->> 'variantId')::uuid),
      'locationId', x."metadata" ->> 'locationId',
      'binId', x."metadata" ->> 'binId',
      'lotId', x."metadata" ->> 'lotId',
      'quantity', x."metadata" ->> 'quantity',
      'unit', x."metadata" ->> 'unit',
      'reason', x."metadata" ->> 'reason',
      'note', x."memo",
      'actorId', x."actor_id",
      'documentType', x."reference_type",
      'documentId', x."reference_id",
      'effectiveAt', x."effective_at") as j, jsonb_build_array((x."effective_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = page_inventory_movements.tenant
        and x."kind" like 'stock.%'
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or (x."metadata" ->> 'variantId')::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (x."metadata" ->> 'variantId')::uuid in (select v."id" from "better_supabase"."product_variants" v where (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (v."product_id")::text = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::text[]))))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or (x."metadata" ->> 'locationId')::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or (x."metadata" ->> 'binId')::text = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or (x."metadata" ->> 'lotId')::text = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or (x."reference_type")::text = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or (x."reference_id")::text = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
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
      'productId', (select v."product_id" from "better_supabase"."product_variants" v where v."id" = (x."metadata" ->> 'variantId')::uuid),
      'locationId', x."metadata" ->> 'locationId',
      'binId', x."metadata" ->> 'binId',
      'lotId', x."metadata" ->> 'lotId',
      'quantity', x."metadata" ->> 'quantity',
      'unit', x."metadata" ->> 'unit',
      'reason', x."metadata" ->> 'reason',
      'note', x."memo",
      'actorId', x."actor_id",
      'documentType', x."reference_type",
      'documentId', x."reference_id",
      'effectiveAt', x."effective_at") as j, jsonb_build_array((x."effective_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = page_inventory_movements.tenant
        and x."kind" like 'stock.%'
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or (x."metadata" ->> 'variantId')::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (x."metadata" ->> 'variantId')::uuid in (select v."id" from "better_supabase"."product_variants" v where (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (v."product_id")::text = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::text[]))))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or (x."metadata" ->> 'locationId')::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or (x."metadata" ->> 'binId')::text = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or (x."metadata" ->> 'lotId')::text = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or (x."reference_type")::text = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or (x."reference_id")::text = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
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
      'productId', (select v."product_id" from "better_supabase"."product_variants" v where v."id" = (x."metadata" ->> 'variantId')::uuid),
      'locationId', x."metadata" ->> 'locationId',
      'binId', x."metadata" ->> 'binId',
      'lotId', x."metadata" ->> 'lotId',
      'quantity', x."metadata" ->> 'quantity',
      'unit', x."metadata" ->> 'unit',
      'reason', x."metadata" ->> 'reason',
      'note', x."memo",
      'actorId', x."actor_id",
      'documentType', x."reference_type",
      'documentId', x."reference_id",
      'effectiveAt', x."effective_at") as j, jsonb_build_array((x."effective_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = page_inventory_movements.tenant
        and x."kind" like 'stock.%'
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or (x."metadata" ->> 'variantId')::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (x."metadata" ->> 'variantId')::uuid in (select v."id" from "better_supabase"."product_variants" v where (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (v."product_id")::text = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::text[]))))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or (x."metadata" ->> 'locationId')::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or (x."metadata" ->> 'binId')::text = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or (x."metadata" ->> 'lotId')::text = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or (x."reference_type")::text = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or (x."reference_id")::text = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
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
      'productId', (select v."product_id" from "better_supabase"."product_variants" v where v."id" = (x."metadata" ->> 'variantId')::uuid),
      'locationId', x."metadata" ->> 'locationId',
      'binId', x."metadata" ->> 'binId',
      'lotId', x."metadata" ->> 'lotId',
      'quantity', x."metadata" ->> 'quantity',
      'unit', x."metadata" ->> 'unit',
      'reason', x."metadata" ->> 'reason',
      'note', x."memo",
      'actorId', x."actor_id",
      'documentType', x."reference_type",
      'documentId', x."reference_id",
      'effectiveAt', x."effective_at") as j, jsonb_build_array((abs(coalesce((x."metadata" ->> 'quantity')::numeric, 0)))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = page_inventory_movements.tenant
        and x."kind" like 'stock.%'
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or (x."metadata" ->> 'variantId')::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (x."metadata" ->> 'variantId')::uuid in (select v."id" from "better_supabase"."product_variants" v where (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (v."product_id")::text = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::text[]))))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or (x."metadata" ->> 'locationId')::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or (x."metadata" ->> 'binId')::text = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or (x."metadata" ->> 'lotId')::text = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or (x."reference_type")::text = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or (x."reference_id")::text = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
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
      'productId', (select v."product_id" from "better_supabase"."product_variants" v where v."id" = (x."metadata" ->> 'variantId')::uuid),
      'locationId', x."metadata" ->> 'locationId',
      'binId', x."metadata" ->> 'binId',
      'lotId', x."metadata" ->> 'lotId',
      'quantity', x."metadata" ->> 'quantity',
      'unit', x."metadata" ->> 'unit',
      'reason', x."metadata" ->> 'reason',
      'note', x."memo",
      'actorId', x."actor_id",
      'documentType', x."reference_type",
      'documentId', x."reference_id",
      'effectiveAt', x."effective_at") as j, jsonb_build_array((abs(coalesce((x."metadata" ->> 'quantity')::numeric, 0)))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = page_inventory_movements.tenant
        and x."kind" like 'stock.%'
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or (x."metadata" ->> 'variantId')::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (x."metadata" ->> 'variantId')::uuid in (select v."id" from "better_supabase"."product_variants" v where (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (v."product_id")::text = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::text[]))))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or (x."metadata" ->> 'locationId')::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or (x."metadata" ->> 'binId')::text = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or (x."metadata" ->> 'lotId')::text = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or (x."reference_type")::text = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or (x."reference_id")::text = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
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
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'variantId' is not null and jsonb_typeof(v_filters -> 'variantId') <> 'null' and not (jsonb_typeof(v_filters -> 'variantId') = 'array' and jsonb_array_length(v_filters -> 'variantId') = 0)) or (x."metadata" ->> 'variantId')::text = any((case when jsonb_typeof(v_filters -> 'variantId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'variantId')) else array[v_filters ->> 'variantId'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (x."metadata" ->> 'variantId')::uuid in (select v."id" from "better_supabase"."product_variants" v where (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or (v."product_id")::text = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::text[]))))
        and (not (v_filters -> 'locationId' is not null and jsonb_typeof(v_filters -> 'locationId') <> 'null' and not (jsonb_typeof(v_filters -> 'locationId') = 'array' and jsonb_array_length(v_filters -> 'locationId') = 0)) or (x."metadata" ->> 'locationId')::text = any((case when jsonb_typeof(v_filters -> 'locationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'locationId')) else array[v_filters ->> 'locationId'] end)::text[]))
        and (not (v_filters -> 'binId' is not null and jsonb_typeof(v_filters -> 'binId') <> 'null' and not (jsonb_typeof(v_filters -> 'binId') = 'array' and jsonb_array_length(v_filters -> 'binId') = 0)) or (x."metadata" ->> 'binId')::text = any((case when jsonb_typeof(v_filters -> 'binId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'binId')) else array[v_filters ->> 'binId'] end)::text[]))
        and (not (v_filters -> 'lotId' is not null and jsonb_typeof(v_filters -> 'lotId') <> 'null' and not (jsonb_typeof(v_filters -> 'lotId') = 'array' and jsonb_array_length(v_filters -> 'lotId') = 0)) or (x."metadata" ->> 'lotId')::text = any((case when jsonb_typeof(v_filters -> 'lotId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'lotId')) else array[v_filters ->> 'lotId'] end)::text[]))
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or (x."reference_type")::text = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'documentId' is not null and jsonb_typeof(v_filters -> 'documentId') <> 'null' and not (jsonb_typeof(v_filters -> 'documentId') = 'array' and jsonb_array_length(v_filters -> 'documentId') = 0)) or (x."reference_id")::text = any((case when jsonb_typeof(v_filters -> 'documentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentId')) else array[v_filters ->> 'documentId'] end)::text[]))
        and (v_search is null or x."kind" ilike v_search or x."reference_id" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.row_visible (
  rel        regclass,
  key_column name,
  key_value  anyelement
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_role name := coalesce(nullif(current_setting('role', true), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user);
  v_using text;
  v_found boolean;
begin
  if not has_table_privilege(v_role, rel, 'select') then
    return false;
  end if;
  if coalesce((select r.rolbypassrls from pg_catalog.pg_roles r where r.rolname = v_role), false)
    or not (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = rel) then
    v_using := 'true';
  else
    select '(' || coalesce(string_agg('(' || coalesce(pg_catalog.pg_get_expr(p.polqual, p.polrelid), 'true') || ')', ' or ') filter (where p.polpermissive), 'false') || ')'
        || coalesce(' and ' || string_agg('(' || coalesce(pg_catalog.pg_get_expr(p.polqual, p.polrelid), 'true') || ')', ' and ') filter (where not p.polpermissive), '')
      into v_using
    from pg_catalog.pg_policy p
    where p.polrelid = rel
      and p.polcmd in ('r', '*')
      and (0::oid = any (p.polroles) or exists (select 1 from unnest(p.polroles) o where pg_catalog.pg_has_role(v_role, o, 'usage')));
  end if;
  execute format('select exists (select 1 from %s where %I = $1 and (%s))', rel, key_column, v_using)
    into v_found using key_value;
  return coalesce(v_found, false);
exception when others then
  return false;
end;
$function$;
