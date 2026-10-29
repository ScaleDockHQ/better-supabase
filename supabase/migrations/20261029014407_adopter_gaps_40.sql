SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.save_category (
  tenant      uuid,
  category    uuid,
  parent      uuid,
  name        text,
  slug        text,
  description text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_category.category;
  v_slug text := coalesce(nullif(save_category.slug, ''), trim(both '-' from regexp_replace(lower(save_category.name), '[^a-z0-9]+', '-', 'g')));
  v_last text;
  v_rank text;
  v_defaults jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_id is null then
    if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_category.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  else
    if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_category.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  end if;
  if v_slug is null or v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'the slug must be lower-case letters, digits and hyphens' using errcode = '22023', hint = 'CATALOG_SLUG_INVALID';
  end if;
  if save_category.parent is not null and not exists (select 1 from "better_supabase"."categories" x where x."id" = save_category.parent and x."tenant_id" = save_category.tenant) then
    raise exception 'parent category not found' using errcode = 'P0002', hint = 'CATALOG_CATEGORY_NOT_FOUND';
  end if;
  if save_category.parent is not null and exists (
    with recursive up (id) as (
      select save_category.parent
      union
      select x."parent_id" from "better_supabase"."categories" x join up on x."id" = up.id where x."parent_id" is not null
    )
    select 1 from up where up.id = v_id
  ) then
    raise exception 'a category can''t sit under itself' using errcode = '22023', hint = 'CATALOG_CATEGORY_CYCLE';
  end if;
  begin
    if v_id is null then
      select max(x."rank" collate "C") into v_last from "better_supabase"."categories" x
      where x."tenant_id" = save_category.tenant and x."parent_id" is not distinct from save_category.parent;
      v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
      execute coalesce((select 'select jsonb_build_object(' || string_agg(pg_catalog.quote_literal(a.attname) || ', ' || pg_catalog.pg_get_expr(d.adbin, d.adrelid), ', ') || ')'
    from pg_catalog.pg_attrdef d join pg_catalog.pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
    where d.adrelid = '"better_supabase"."categories"'::regclass and a.attname = any (array[case when save_category.description is null then 'description' end]::text[])), 'select ''{}''::jsonb') into v_defaults;
      insert into "better_supabase"."categories" ("tenant_id", "parent_id", "name", "slug", "description", "rank")
      values (save_category.tenant, save_category.parent, save_category.name, v_slug, coalesce(save_category.description, (jsonb_populate_record(null::"better_supabase"."categories", v_defaults))."description"), v_rank)
      returning "id" into v_id;
    else
      update "better_supabase"."categories" x set "parent_id" = save_category.parent, "name" = save_category.name, "slug" = v_slug,
        "description" = save_category.description, "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_category.tenant
      returning x."rank" into v_rank;
      if not found then
        raise exception 'category not found' using errcode = 'P0002', hint = 'CATALOG_CATEGORY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    declare
      v_constraint text;
    begin
      get stacked diagnostics v_constraint = constraint_name;
      if exists (
        select 1 from pg_catalog.pg_index i
        join pg_catalog.pg_class c on c.oid = i.indexrelid
        where i.indrelid = '"better_supabase"."categories"'::regclass and c.relname = v_constraint
          and (exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = i.indrelid and a.attnum = any (i.indkey) and a.attname = 'slug')
            or coalesce(pg_catalog.pg_get_expr(i.indexprs, i.indrelid), '') ~ ('\m' || 'slug' || '\M'))
      ) then
        raise exception 'another category has this slug' using errcode = '23505', hint = 'CATALOG_SLUG_TAKEN';
      end if;
      raise;
    end;
  end;
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'rank', v_rank);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_product (
  tenant      uuid,
  product     uuid,
  title       text,
  slug        text,
  description text,
  kind        text,
  clear       text[] DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_product.product;
  v_title text := save_product.title;
  v_slug text := nullif(save_product.slug, '');
  v_status text;
  v_created boolean := save_product.product is null;
  v_defaults jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_created then
    if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_product.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  else
    if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_product.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  end if;
  if exists (select 1 from unnest(coalesce(save_product.clear, '{}'::text[])) c where c <> all ('{slug,description}'::text[])) then
    raise exception 'clear names only slug, description' using errcode = '22023', hint = 'CATALOG_CLEAR_INVALID';
  end if;
  if not v_created then
    select coalesce(v_title, x."title"), case when v_slug is null and not 'slug' = any (coalesce(save_product.clear, '{}'::text[])) then x."slug" else v_slug end
    into v_title, v_slug
    from "better_supabase"."products" x where x."id" = save_product.product and x."tenant_id" = save_product.tenant;
    if not found then
      raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
    end if;
  end if;
  v_slug := coalesce(v_slug, trim(both '-' from regexp_replace(lower(v_title), '[^a-z0-9]+', '-', 'g')));
  if v_slug is null or v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'the slug must be lower-case letters, digits and hyphens' using errcode = '22023', hint = 'CATALOG_SLUG_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_product_save"(uuid, uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text, $5::text)', v_hook::oid::regproc)
        using save_product.tenant, save_product.product, v_title, v_slug, save_product.kind;
    end if;
  end;
  begin
    if v_created then
      execute coalesce((select 'select jsonb_build_object(' || string_agg(pg_catalog.quote_literal(a.attname) || ', ' || pg_catalog.pg_get_expr(d.adbin, d.adrelid), ', ') || ')'
    from pg_catalog.pg_attrdef d join pg_catalog.pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
    where d.adrelid = '"better_supabase"."products"'::regclass and a.attname = any (array[case when save_product.description is null then 'description' end]::text[])), 'select ''{}''::jsonb') into v_defaults;
      insert into "better_supabase"."products" ("tenant_id", "title", "slug", "description", "kind")
      values (save_product.tenant, v_title, v_slug, coalesce(save_product.description, (jsonb_populate_record(null::"better_supabase"."products", v_defaults))."description"), coalesce(save_product.kind, 'physical'))
      returning "id", "status" into v_id, v_status;
    else
      update "better_supabase"."products" x set "title" = v_title, "slug" = v_slug, "description" = case when 'description' = any (coalesce(save_product.clear, '{}'::text[])) then null else coalesce(save_product.description, x."description") end, "kind" = coalesce(save_product.kind, x."kind"), "updated_at" = now()
      where x."id" = save_product.product and x."tenant_id" = save_product.tenant
      returning x."status" into v_status;
      if not found then
        raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    declare
      v_constraint text;
    begin
      get stacked diagnostics v_constraint = constraint_name;
      if exists (
        select 1 from pg_catalog.pg_index i
        join pg_catalog.pg_class c on c.oid = i.indexrelid
        where i.indrelid = '"better_supabase"."products"'::regclass and c.relname = v_constraint
          and (exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = i.indrelid and a.attnum = any (i.indkey) and a.attname = 'slug')
            or coalesce(pg_catalog.pg_get_expr(i.indexprs, i.indrelid), '') ~ ('\m' || 'slug' || '\M'))
      ) then
        raise exception 'another product has this slug' using errcode = '23505', hint = 'CATALOG_SLUG_TAKEN';
      end if;
      raise;
    end;
  end;
  if v_created then
    perform "better_supabase".emit_event('product.created', jsonb_build_object('organizationId', save_product.tenant, 'id', v_id, 'slug', v_slug, 'kind', coalesce(save_product.kind, 'physical')), 'products/' || v_id::text, (save_product.tenant)::text, null, 'better-supabase/catalog');
  else
    perform "better_supabase".emit_event('product.updated', jsonb_build_object('organizationId', save_product.tenant, 'id', v_id, 'slug', v_slug), 'products/' || v_id::text, (save_product.tenant)::text, null, 'better-supabase/catalog');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_product_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_id, v_created;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'status', v_status);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_variant (
  product         uuid,
  variant         uuid,
  sku             text,
  option_values   uuid[],
  title           text,
  barcode         text,
  weight_grams    integer,
  track_inventory boolean,
  allow_backorder boolean,
  clear           text[]  DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_id uuid := save_variant.variant;
  v_created boolean := save_variant.variant is null;
  v_wanted uuid[];
  v_last text;
  v_rank text;
  v_sku text := save_variant.sku;
  v_defaults jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."products" x where x."id" = save_variant.product for update;
  if v_tenant is null then
    raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
  end if;
  if v_created then
    if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  else
    if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  end if;
  if exists (select 1 from unnest(coalesce(save_variant.clear, '{}'::text[])) c where c <> all ('{sku,title,barcode,weight}'::text[])) then
    raise exception 'clear names only sku, title, barcode, weight' using errcode = '22023', hint = 'CATALOG_CLEAR_INVALID';
  end if;
  if v_created or save_variant.option_values is not null then
  v_wanted := coalesce((select array_agg(distinct x order by x) from unnest(save_variant.option_values) x), '{}'::uuid[]);
  if cardinality(v_wanted) <> coalesce(cardinality(save_variant.option_values), 0)
    or exists (
      select 1 from unnest(v_wanted) x
      where not exists (
        select 1 from "better_supabase"."product_option_values" ov join "better_supabase"."product_options" o on o."id" = ov."option_id"
        where ov."id" = x and o."product_id" = save_variant.product
      )
    )
    or (select count(distinct ov."option_id") from "better_supabase"."product_option_values" ov where ov."id" = any (v_wanted)) <> cardinality(v_wanted)
    or (select count(*) from "better_supabase"."product_options" o where o."product_id" = save_variant.product) <> cardinality(v_wanted) then
    raise exception 'a variant needs exactly one value of each product option' using errcode = '22023', hint = 'CATALOG_VARIANT_OPTIONS';
  end if;
  if exists (
    select 1 from "better_supabase"."product_variants" x
    where x."product_id" = save_variant.product
      and x."id" is distinct from save_variant.variant
      and coalesce((select array_agg(y."option_value_id" order by y."option_value_id") from "better_supabase"."product_variant_values" y where y."variant_id" = x."id"), '{}'::uuid[]) = v_wanted
  ) then
    raise exception 'another variant has these option values' using errcode = '23505', hint = 'CATALOG_VARIANT_DUPLICATE';
  end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_variant_save"(uuid, uuid, text, uuid[])');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::uuid[])', v_hook::oid::regproc)
        using save_variant.product, save_variant.variant, save_variant.sku, v_wanted;
    end if;
  end;
  begin
    if v_created then
      select max(x."rank" collate "C") into v_last from "better_supabase"."product_variants" x where x."product_id" = save_variant.product;
      v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
      execute coalesce((select 'select jsonb_build_object(' || string_agg(pg_catalog.quote_literal(a.attname) || ', ' || pg_catalog.pg_get_expr(d.adbin, d.adrelid), ', ') || ')'
    from pg_catalog.pg_attrdef d join pg_catalog.pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
    where d.adrelid = '"better_supabase"."product_variants"'::regclass and a.attname = any (array[case when save_variant.sku is null then 'sku' end, case when save_variant.title is null then 'title' end, case when save_variant.barcode is null then 'barcode' end, case when save_variant.weight_grams is null then 'weight_grams' end]::text[])), 'select ''{}''::jsonb') into v_defaults;
      insert into "better_supabase"."product_variants" as x ("tenant_id", "product_id", "sku", "title", "barcode", "weight_grams", "track_inventory", "allow_backorder", "rank")
      values (v_tenant, save_variant.product, coalesce(save_variant.sku, (jsonb_populate_record(null::"better_supabase"."product_variants", v_defaults))."sku"), coalesce(save_variant.title, (jsonb_populate_record(null::"better_supabase"."product_variants", v_defaults))."title"), coalesce(save_variant.barcode, (jsonb_populate_record(null::"better_supabase"."product_variants", v_defaults))."barcode"), coalesce(save_variant.weight_grams, (jsonb_populate_record(null::"better_supabase"."product_variants", v_defaults))."weight_grams"), coalesce(save_variant.track_inventory, true), coalesce(save_variant.allow_backorder, false), v_rank)
      returning x."id", x."sku" into v_id, v_sku;
    else
      update "better_supabase"."product_variants" x set "sku" = case when 'sku' = any (coalesce(save_variant.clear, '{}'::text[])) then null else coalesce(save_variant.sku, x."sku") end, "title" = case when 'title' = any (coalesce(save_variant.clear, '{}'::text[])) then null else coalesce(save_variant.title, x."title") end, "barcode" = case when 'barcode' = any (coalesce(save_variant.clear, '{}'::text[])) then null else coalesce(save_variant.barcode, x."barcode") end, "weight_grams" = case when 'weight' = any (coalesce(save_variant.clear, '{}'::text[])) then null else coalesce(save_variant.weight_grams, x."weight_grams") end, "track_inventory" = coalesce(save_variant.track_inventory, x."track_inventory"), "allow_backorder" = coalesce(save_variant.allow_backorder, x."allow_backorder"), "updated_at" = now()
      where x."id" = save_variant.variant and x."product_id" = save_variant.product
      returning x."rank", x."sku" into v_rank, v_sku;
      if not found then
        raise exception 'variant not found' using errcode = 'P0002', hint = 'CATALOG_VARIANT_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    declare
      v_constraint text;
    begin
      get stacked diagnostics v_constraint = constraint_name;
      if exists (
        select 1 from pg_catalog.pg_index i
        join pg_catalog.pg_class c on c.oid = i.indexrelid
        where i.indrelid = '"better_supabase"."product_variants"'::regclass and c.relname = v_constraint
          and (exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = i.indrelid and a.attnum = any (i.indkey) and a.attname = 'sku')
            or coalesce(pg_catalog.pg_get_expr(i.indexprs, i.indrelid), '') ~ ('\m' || 'sku' || '\M'))
      ) then
        raise exception 'another variant has this SKU' using errcode = '23505', hint = 'CATALOG_SKU_TAKEN';
      end if;
      raise;
    end;
  end;
  if v_wanted is not null then
  delete from "better_supabase"."product_variant_values" x where x."variant_id" = v_id and not (x."option_value_id" = any (v_wanted));
  insert into "better_supabase"."product_variant_values" ("tenant_id", "variant_id", "option_value_id")
  select v_tenant, v_id, x from unnest(v_wanted) x
  on conflict do nothing;
  end if;
  if v_created then
    perform "better_supabase".emit_event('variant.created', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'productId', save_variant.product, 'sku', v_sku), 'variants/' || v_id::text, (v_tenant)::text, null, 'better-supabase/catalog');
  else
    perform "better_supabase".emit_event('variant.updated', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'productId', save_variant.product, 'sku', v_sku), 'variants/' || v_id::text, (v_tenant)::text, null, 'better-supabase/catalog');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_variant_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_id, v_created;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'sku', v_sku, 'rank', v_rank);
end;
$function$;
