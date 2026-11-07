SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."stock_levels"
  ADD COLUMN "reorder_quantity" numeric(20,6);

CREATE OR REPLACE FUNCTION api.pick_serials (
  variant  uuid,
  location uuid,
  quantity integer,
  lot      uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."pick_serials"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.set_reorder_quantity (
  variant          uuid,
  location         uuid,
  reorder_quantity numeric
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_reorder_quantity"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.pick_serials (
  variant  uuid,
  location uuid,
  quantity integer,
  lot      uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_serials jsonb;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = pick_serials.location;
  if v_tenant is null or not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if pick_serials.quantity is null or pick_serials.quantity <= 0 then
    raise exception 'the quantity must be greater than zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  select jsonb_agg(z."serial" order by z."updated_at", z."serial") into v_serials from (
    select y."serial", y."updated_at" from "better_supabase"."stock_serials" y
    where y."variant_id" = pick_serials.variant and y."location_id" = pick_serials.location
      and y."status" = 'in_stock' and (pick_serials.lot is null or y."lot_id" = pick_serials.lot)
    order by y."updated_at", y."serial" limit pick_serials.quantity
  ) z;
  if coalesce(jsonb_array_length(v_serials), 0) < pick_serials.quantity then
    raise exception 'not enough stock available' using errcode = '23514', hint = 'INVENTORY_INSUFFICIENT';
  end if;
  return v_serials;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_reorder_quantity (
  variant          uuid,
  location         uuid,
  reorder_quantity numeric
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."active" into v_tenant, v_active from "better_supabase"."inventory_locations" x where x."id" = set_reorder_quantity.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = set_reorder_quantity.variant and cv."tenant_id" = v_tenant) then
    raise exception 'variant not found in this organization' using errcode = 'P0002', hint = 'INVENTORY_VARIANT_NOT_FOUND';
  end if;
  if set_reorder_quantity.reorder_quantity is not null and set_reorder_quantity.reorder_quantity <= 0 then
    raise exception 'the quantity must be greater than zero' using errcode = '22023', hint = 'INVENTORY_QUANTITY_INVALID';
  end if;
  insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "reorder_quantity")
  values (v_tenant, set_reorder_quantity.variant, set_reorder_quantity.location, set_reorder_quantity.reorder_quantity)
  on conflict ("variant_id", "location_id") do update
    set "reorder_quantity" = excluded."reorder_quantity", "updated_at" = now();
  return true;
end;
$function$;

ALTER TABLE "better_supabase"."inventory_locations"
  ADD CONSTRAINT "inventory_locations_id_tenant_id_key" UNIQUE (id, tenant_id);

ALTER TABLE "better_supabase"."purchase_orders"
  ADD CONSTRAINT "purchase_orders_id_tenant_id_key" UNIQUE (id, tenant_id);

ALTER TABLE "better_supabase"."stock_levels"
  ADD CONSTRAINT "bsb_stock_levels_reorder_quantity" CHECK ((reorder_quantity > (0)::numeric));

ALTER TABLE "better_supabase"."stock_reservations"
  ADD CONSTRAINT "stock_reservations_id_tenant_id_key" UNIQUE (id, tenant_id);

ALTER TABLE "better_supabase"."stock_transfers"
  ADD CONSTRAINT "stock_transfers_id_tenant_id_key" UNIQUE (id, tenant_id);

REVOKE ALL ON FUNCTION "api"."pick_serials"(uuid, uuid, integer, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."pick_serials"(uuid, uuid, integer, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_reorder_quantity"(uuid, uuid, numeric) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_reorder_quantity"(uuid, uuid, numeric) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."pick_serials"(uuid, uuid, integer, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."pick_serials"(uuid, uuid, integer, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_reorder_quantity"(uuid, uuid, numeric) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_reorder_quantity"(uuid, uuid, numeric) TO "authenticated", "service_role";
