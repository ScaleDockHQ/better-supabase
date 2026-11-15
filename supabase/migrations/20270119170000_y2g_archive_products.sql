SET local check_function_bodies = off;

DROP FUNCTION "api"."channel_products"(uuid, text, integer, text);

DROP FUNCTION "api"."delete_product"(uuid);

DROP FUNCTION "api"."delete_variant"(uuid);

DROP FUNCTION "better_supabase"."channel_products"(uuid, text, integer, text);

DROP FUNCTION "better_supabase"."delete_product"(uuid);

DROP FUNCTION "better_supabase"."delete_variant"(uuid);

CREATE OR REPLACE FUNCTION api.archive_product (
  product uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_product"($1) $function$;

CREATE OR REPLACE FUNCTION api.archive_variant (
  variant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_variant"($1) $function$;

CREATE OR REPLACE FUNCTION api.channel_products (
  channel   uuid,
  locale    text    DEFAULT NULL::text,
  page_size integer DEFAULT NULL::integer,
  after     text    DEFAULT NULL::text,
  archived  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."channel_products"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.purge_product (
  product uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_product"($1) $function$;

CREATE OR REPLACE FUNCTION api.purge_variant (
  variant uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_variant"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_product (
  product uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_product"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_variant (
  variant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_variant"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_product (
  product uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return "better_supabase"."set_product_status"(archive_product.product, 'archived');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_variant (
  variant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  raise exception 'this variants table has no status column' using errcode = '22023', hint = 'CATALOG_VARIANT_STATUS_UNSUPPORTED';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.channel_products (
  channel   uuid,
  locale    text    DEFAULT NULL::text,
  page_size integer DEFAULT NULL::integer,
  after     text    DEFAULT NULL::text,
  archived  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(item order by slug collate "C"), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', p."id",
      'slug', p."slug",
      'status', p."status",
      'kind', p."kind",
      'locale', (case when $2 = any ('{en}'::text[]) then $2 when split_part($2, '-', 1) = any ('{en}'::text[]) then split_part($2, '-', 1) else 'en' end),
      'title', coalesce(t."title", p."title"),
      'description', coalesce(t."description", p."description"),
      'listedAt', l."listed_at"
    ) as item, p."slug" as slug
    from "better_supabase"."catalog_channel_products" l
    join "better_supabase"."products" p on p."id" = l."product_id"
    left join "better_supabase"."product_translations" t on t."product_id" = p."id" and t."locale" = (case when $2 = any ('{en}'::text[]) then $2 when split_part($2, '-', 1) = any ('{en}'::text[]) then split_part($2, '-', 1) else 'en' end)
    where l."channel_id" = $1
      and ($4 is null or p."slug" collate "C" > $4 collate "C")
      and (case when coalesce($5, false) then p."status" = 'archived' else p."status" <> 'archived' end)
    order by p."slug" collate "C"
    limit least(greatest(coalesce($3, 100), 1), 500)
  ) items
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_product (
  product uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."products" x where x."id" = purge_product.product;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" sa where sa."managed_by" = 'inventory' and sa."kind" = 'stock' and (case when sa."kind" = 'stock' then (sa."metadata" ->> 'variantId')::uuid end) in (select v."id" from "better_supabase"."product_variants" v where v."product_id" = purge_product.product)) then
    raise exception 'the stock ledger has movements for this record; archive it instead' using errcode = '23503', hint = 'CATALOG_PRODUCT_IN_USE';
  end if;
  delete from "better_supabase"."products" x where x."id" = purge_product.product;
  perform "better_supabase".emit_event('product.purged', jsonb_build_object('organizationId', v_tenant, 'id', purge_product.product), 'products/' || purge_product.product::text, (v_tenant)::text, null, 'better-supabase/catalog');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_variant (
  variant uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_product uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."product_id" into v_tenant, v_product from "better_supabase"."product_variants" x where x."id" = purge_variant.variant;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" sa where sa."managed_by" = 'inventory' and sa."kind" = 'stock' and (case when sa."kind" = 'stock' then (sa."metadata" ->> 'variantId')::uuid end) in (purge_variant.variant)) then
    raise exception 'the stock ledger has movements for this record; archive it instead' using errcode = '23503', hint = 'CATALOG_VARIANT_IN_USE';
  end if;
  delete from "better_supabase"."product_variants" x where x."id" = purge_variant.variant;
  perform "better_supabase".emit_event('product_variant.purged', jsonb_build_object('organizationId', v_tenant, 'id', purge_variant.variant, 'productId', v_product), 'variants/' || purge_variant.variant::text, (v_tenant)::text, null, 'better-supabase/catalog');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_product (
  product uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_status text;
begin
  select x."status" into v_status from "better_supabase"."products" x where x."id" = restore_product.product;
  if v_status is distinct from 'archived' then
    return "better_supabase"."set_product_status"(restore_product.product, coalesce(v_status, 'archived'));
  end if;
  return "better_supabase"."set_product_status"(restore_product.product, 'draft');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_variant (
  variant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  raise exception 'this variants table has no status column' using errcode = '22023', hint = 'CATALOG_VARIANT_STATUS_UNSUPPORTED';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_product_option (
  product       uuid,
  option        uuid,
  name          text,
  option_values text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_id uuid := save_product_option.option;
  v_last text;
  v_rank text;
  v_value text;
  v_variant uuid;
  v_new boolean := save_product_option.option is null;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."products" x where x."id" = save_product_option.product for update;
  if v_tenant is null then
    raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if coalesce(cardinality(save_product_option.option_values), 0) = 0 then
    raise exception 'an option needs at least one value' using errcode = '22023', hint = 'CATALOG_OPTION_EMPTY';
  end if;
  if (select count(distinct x) from unnest(save_product_option.option_values) x) <> cardinality(save_product_option.option_values) then
    raise exception 'an option lists the same value twice' using errcode = '22023', hint = 'CATALOG_OPTION_DUPLICATE';
  end if;
  begin
    if v_id is null then
      select max(x."rank" collate "C") into v_last from "better_supabase"."product_options" x where x."product_id" = save_product_option.product;
      insert into "better_supabase"."product_options" ("tenant_id", "product_id", "name", "rank")
      values (v_tenant, save_product_option.product, save_product_option.name, case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_id;
    else
      update "better_supabase"."product_options" x set "name" = save_product_option.name
      where x."id" = save_product_option.option and x."product_id" = save_product_option.product;
      if not found then
        raise exception 'option not found' using errcode = 'P0002', hint = 'CATALOG_OPTION_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'the product has another option with this name' using errcode = '23505', hint = 'CATALOG_OPTION_TAKEN';
  end;
  for v_variant in
    select distinct x."variant_id" from "better_supabase"."product_variant_values" x
    join "better_supabase"."product_option_values" y on y."id" = x."option_value_id"
    where y."option_id" = v_id and not (y."value" = any (save_product_option.option_values))
  loop
    if exists (select 1 from "better_supabase"."ledger_accounts" sa where sa."managed_by" = 'inventory' and sa."kind" = 'stock' and (case when sa."kind" = 'stock' then (sa."metadata" ->> 'variantId')::uuid end) = v_variant) then
      raise exception 'a variant this list removes is still in use' using errcode = '23503', hint = 'CATALOG_OPTION_VALUE_IN_USE';
      continue;
    end if;
    begin
      delete from "better_supabase"."product_variants" x where x."id" = v_variant;
      perform "better_supabase".emit_event('product_variant.purged', jsonb_build_object('organizationId', v_tenant, 'id', v_variant, 'productId', save_product_option.product), 'variants/' || v_variant::text, (v_tenant)::text, null, 'better-supabase/catalog');
    exception when foreign_key_violation then
      raise exception 'a variant this list removes is still in use' using errcode = '23503', hint = 'CATALOG_OPTION_VALUE_IN_USE';
    end;
  end loop;
  begin
    delete from "better_supabase"."product_option_values" x where x."option_id" = v_id and not (x."value" = any (save_product_option.option_values));
  exception when foreign_key_violation then
    raise exception 'a variant uses a value this list removes' using errcode = '23503', hint = 'CATALOG_OPTION_VALUE_IN_USE';
  end;
  v_rank := null;
  foreach v_value in array save_product_option.option_values loop
    v_rank := case
    when v_rank is null then 'V'
    when length(substring(v_rank from '^z*')) = length(v_rank) then v_rank || 'V'
    else left(v_rank, length(substring(v_rank from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_rank, length(substring(v_rank from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
    update "better_supabase"."product_option_values" x set "rank" = v_rank where x."option_id" = v_id and x."value" = v_value;
    if not found then
      insert into "better_supabase"."product_option_values" ("tenant_id", "option_id", "value", "rank")
      values (v_tenant, v_id, v_value, v_rank);
    end if;
  end loop;
  if v_new then
    insert into "better_supabase"."product_variant_values" ("tenant_id", "variant_id", "option_value_id")
    select v_tenant, x."id", (select y."id" from "better_supabase"."product_option_values" y where y."option_id" = v_id and y."value" = save_product_option.option_values[1])
    from "better_supabase"."product_variants" x where x."product_id" = save_product_option.product;
  end if;
  return jsonb_build_object(
    'id', v_id,
    'values', (select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'value', x."value") order by x."rank" collate "C"), '[]'::jsonb) from "better_supabase"."product_option_values" x where x."option_id" = v_id)
  );
end;
$function$;

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
      perform "better_supabase".emit_event('product_variant.purged', jsonb_build_object('organizationId', v_tenant, 'id', v_variant, 'productId', set_product_options.product), 'variants/' || v_variant::text, (v_tenant)::text, null, 'better-supabase/catalog');
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

CREATE OR REPLACE FUNCTION better_supabase.set_product_status (
  product uuid,
  status  text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_from text;
  v_from_raw text;
  v_to text := set_product_status.status;
  v_to_raw text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."status", x."status"::text into v_tenant, v_from, v_from_raw from "better_supabase"."products" x where x."id" = set_product_status.product for update;
  if v_tenant is null then
    raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if v_to is null or v_to not in ('draft', 'active', 'archived') then
    raise exception 'the status must be draft, active or archived' using errcode = '22023', hint = 'CATALOG_STATUS_INVALID';
  end if;
  v_to_raw := (set_product_status.status)::text;
  if v_from_raw = v_to_raw then
    return jsonb_build_object('id', set_product_status.product, 'status', v_from, 'from', v_from);
  end if;
  if v_from <> v_to and not (case v_from
    when 'draft' then v_to = any ('{active,archived}'::text[])
    when 'active' then v_to = any ('{draft,archived}'::text[])
    when 'archived' then v_to = any ('{draft}'::text[])
    else false
  end) then
    raise exception 'the product can''t move to this status' using errcode = '22023', hint = 'CATALOG_TRANSITION_INVALID';
  end if;
  update "better_supabase"."products" x set "status" = set_product_status.status, "updated_at" = now()
  where x."id" = set_product_status.product;
  perform "better_supabase".emit_event('product.status_changed', jsonb_build_object('organizationId', v_tenant, 'id', set_product_status.product, 'from', v_from, 'to', v_to), 'products/' || set_product_status.product::text, (v_tenant)::text, null, 'better-supabase/catalog');
  if v_to = 'archived' then
    perform "better_supabase".emit_event('product.archived', jsonb_build_object('organizationId', v_tenant, 'id', set_product_status.product), 'products/' || set_product_status.product::text, (v_tenant)::text, null, 'better-supabase/catalog');
  elsif v_from = 'archived' then
    perform "better_supabase".emit_event('product.restored', jsonb_build_object('organizationId', v_tenant, 'id', set_product_status.product), 'products/' || set_product_status.product::text, (v_tenant)::text, null, 'better-supabase/catalog');
  end if;
  return jsonb_build_object('id', set_product_status.product, 'status', v_to, 'from', v_from);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."archive_product"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_product"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."archive_variant"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_variant"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."channel_products"(uuid, text, integer, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."channel_products"(uuid, text, integer, text, boolean) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_product"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_product"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_variant"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_variant"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_product"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_product"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_variant"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_variant"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_product"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_product"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_variant"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_variant"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."channel_products"(uuid, text, integer, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."channel_products"(uuid, text, integer, text, boolean) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_product"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_product"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_variant"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_variant"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_product"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_product"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_variant"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_variant"(uuid) TO "authenticated", "service_role";
