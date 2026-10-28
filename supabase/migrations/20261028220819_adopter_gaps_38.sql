SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.set_product_options (
  product         uuid,
  options         jsonb,
  title_separator text  DEFAULT ' / '::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_product_options"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.set_product_options (
  product         uuid,
  options         jsonb,
  title_separator text  DEFAULT ' / '::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_slug text;
  v_item jsonb;
  v_option uuid;
  v_ids uuid[] := '{}';
  v_variant uuid;
  v_combo uuid[];
  v_label text;
  v_count numeric := 1;
  v_sku_required boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."slug" into v_tenant, v_slug from "better_supabase"."products" x where x."id" = set_product_options.product for update;
  if v_tenant is null then
    raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if jsonb_typeof(set_product_options.options) is distinct from 'array'
    or exists (
      select 1 from jsonb_array_elements(set_product_options.options) e
      where jsonb_typeof(e) is distinct from 'object'
        or jsonb_typeof(e -> 'name') is distinct from 'string'
        or jsonb_typeof(e -> 'values') is distinct from 'array'
        or exists (select 1 from jsonb_array_elements(e -> 'values') y where jsonb_typeof(y) <> 'string')
    ) then
    raise exception 'options is a list of { name, values } with text values' using errcode = '22023', hint = 'CATALOG_OPTIONS_INVALID';
  end if;
  if (select count(distinct e ->> 'name') from jsonb_array_elements(set_product_options.options) e) <> jsonb_array_length(set_product_options.options) then
    raise exception 'the list names an option twice' using errcode = '23505', hint = 'CATALOG_OPTION_TAKEN';
  end if;
  for v_item in select e from jsonb_array_elements(set_product_options.options) e loop
    v_count := v_count * jsonb_array_length(v_item -> 'values');
  end loop;
  if v_count > 100 then
    raise exception 'a product has at most 100 variants' using errcode = '22023', hint = 'CATALOG_VARIANT_LIMIT';
  end if;
  for v_option in
    select x."id" from "better_supabase"."product_options" x
    where x."product_id" = set_product_options.product
      and not (x."name" = any (array(select e ->> 'name' from jsonb_array_elements(set_product_options.options) e)))
  loop
    delete from "better_supabase"."product_variant_values" y using "better_supabase"."product_option_values" z where y."option_value_id" = z."id" and z."option_id" = v_option;
    delete from "better_supabase"."product_options" x where x."id" = v_option;
  end loop;
  for v_variant in
    select d.id from (
      select x."id" as id, row_number() over (partition by coalesce((select array_agg(y."option_value_id" order by y."option_value_id") from "better_supabase"."product_variant_values" y where y."variant_id" = x."id"), '{}'::uuid[]) order by x."rank" collate "C", x."id") as n
      from "better_supabase"."product_variants" x where x."product_id" = set_product_options.product
    ) d where d.n > 1
  loop
    if exists (select 1 from "better_supabase"."ledger_accounts" sa where sa."managed_by" = 'inventory' and sa."kind" = 'stock' and (case when sa."kind" = 'stock' then (sa."metadata" ->> 'variantId')::uuid end) = v_variant) then
      raise exception 'a variant this list removes is still in use' using errcode = '23503', hint = 'CATALOG_OPTION_VALUE_IN_USE';
      continue;
    end if;
    begin
      delete from "better_supabase"."product_variants" x where x."id" = v_variant;
      perform "better_supabase".emit_event('variant.deleted', jsonb_build_object('organizationId', v_tenant, 'id', v_variant, 'productId', set_product_options.product), 'variants/' || v_variant::text, (v_tenant)::text, null, 'better-supabase/catalog');
    exception when foreign_key_violation then
      raise exception 'a variant this list removes is still in use' using errcode = '23503', hint = 'CATALOG_OPTION_VALUE_IN_USE';
    end;
  end loop;
  for v_item in select e from jsonb_array_elements(set_product_options.options) with ordinality as a(e, n) order by a.n loop
    select x."id" into v_option from "better_supabase"."product_options" x where x."product_id" = set_product_options.product and x."name" = v_item ->> 'name';
    v_option := ("better_supabase"."save_product_option"(set_product_options.product, v_option, v_item ->> 'name', array(select y from jsonb_array_elements_text(v_item -> 'values') with ordinality as b(y, n) order by b.n)) ->> 'id')::uuid;
    v_ids := v_ids || v_option;
  end loop;
  if cardinality(v_ids) > 0 then
    perform "better_supabase"."reorder_product_options"(set_product_options.product, v_ids);
  end if;
  select a.attnotnull into v_sku_required from pg_catalog.pg_attribute a
  where a.attrelid = '"better_supabase"."product_variants"'::regclass and a.attname = 'sku';
  for v_combo, v_label in
    with recursive k as (
      select x."id" as id, row_number() over (order by x."rank" collate "C") as n
      from "better_supabase"."product_options" x where x."product_id" = set_product_options.product
    ), z as (
      select y."id" as id, y."value" as value, y."option_id" as option, row_number() over (partition by y."option_id" order by y."rank" collate "C") as n
      from "better_supabase"."product_option_values" y where y."option_id" in (select k.id from k)
    ), c(depth, ids, labels, sort) as (
      select 0::bigint, '{}'::uuid[], '{}'::text[], '{}'::bigint[]
      union all
      select k.n, c.ids || z.id, c.labels || z.value, c.sort || z.n
      from c join k on k.n = c.depth + 1 join z on z.option = k.id
    )
    select c.ids, array_to_string(c.labels, '-') from c where c.depth = (select count(*) from k) order by c.sort
  loop
    if not exists (
      select 1 from "better_supabase"."product_variants" x
      where x."product_id" = set_product_options.product
        and coalesce((select array_agg(y."option_value_id" order by y."option_value_id") from "better_supabase"."product_variant_values" y where y."variant_id" = x."id"), '{}'::uuid[]) = (select coalesce(array_agg(u order by u), '{}'::uuid[]) from unnest(v_combo) u)
    ) then
      perform "better_supabase"."save_variant"(set_product_options.product, null, case when v_sku_required then upper(trim(both '-' from regexp_replace(concat_ws('-', v_slug, nullif(v_label, '')), '[^A-Za-z0-9]+', '-', 'g'))) end, v_combo, null, null, null, null, null);
    end if;
  end loop;
  if set_product_options.title_separator is not null then
    update "better_supabase"."product_variants" x set "title" = t.title, "updated_at" = now()
    from (
      select y."variant_id" as variant, string_agg(z."value", set_product_options.title_separator order by k."rank" collate "C") as title
      from "better_supabase"."product_variant_values" y
      join "better_supabase"."product_option_values" z on z."id" = y."option_value_id"
      join "better_supabase"."product_options" k on k."id" = z."option_id"
      where k."product_id" = set_product_options.product
      group by y."variant_id"
    ) t
    where x."id" = t.variant and x."title" is distinct from t.title;
  end if;
  return jsonb_build_object(
    'options', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', k."id",
        'name', k."name",
        'values', (select coalesce(jsonb_agg(jsonb_build_object('id', z."id", 'value', z."value") order by z."rank" collate "C"), '[]'::jsonb) from "better_supabase"."product_option_values" z where z."option_id" = k."id")
      ) order by k."rank" collate "C"), '[]'::jsonb)
      from "better_supabase"."product_options" k where k."product_id" = set_product_options.product
    ),
    'variants', (
      select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'sku', x."sku", 'optionValueIds', to_jsonb(coalesce((select array_agg(y."option_value_id" order by y."option_value_id") from "better_supabase"."product_variant_values" y where y."variant_id" = x."id"), '{}'::uuid[]))) order by x."rank" collate "C"), '[]'::jsonb)
      from "better_supabase"."product_variants" x where x."product_id" = set_product_options.product
    )
  );
end;
$function$;

REVOKE ALL ON FUNCTION "api"."set_product_options"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_product_options"(uuid, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_product_options"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_product_options"(uuid, jsonb, text) TO "authenticated", "service_role";
