SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.inventory_overview (
  tenant      uuid,
  row_limit   integer DEFAULT 20,
  expiry_days integer DEFAULT 30
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."inventory_overview"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.sessions_overview()
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."sessions_overview"() $function$;

CREATE OR REPLACE FUNCTION better_supabase.inventory_overview (
  tenant      uuid,
  row_limit   integer DEFAULT 20,
  expiry_days integer DEFAULT 30
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_low jsonb;
  v_low_count integer;
  v_level_count integer;
  v_expiring jsonb;
begin
  select count(*)::integer into v_level_count
  from "better_supabase"."stock_levels" y where y."tenant_id" = inventory_overview.tenant;

  select count(*)::integer into v_low_count
  from "better_supabase"."stock_levels" y
  where y."tenant_id" = inventory_overview.tenant
    and y."reorder_point" is not null and y."available" <= y."reorder_point";

  select coalesce(jsonb_agg(jsonb_build_object(
      'variantId', x."variant_id", 'locationId', x."location_id",
      'onHand', x."on_hand"::text, 'available', x."available"::text,
      'reorderPoint', x."reorder_point"::text)
    order by x."available" - x."reorder_point", x."variant_id", x."location_id"), '[]'::jsonb)
  into v_low
  from (
    select * from "better_supabase"."stock_levels" y
    where y."tenant_id" = inventory_overview.tenant
      and y."reorder_point" is not null and y."available" <= y."reorder_point"
    order by y."available" - y."reorder_point", y."variant_id", y."location_id"
    limit greatest(coalesce(inventory_overview.row_limit, 20), 0)
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object(
      'lotId', e ->> 'lotId', 'code', e ->> 'code', 'variantId', e ->> 'variantId',
      'locationId', e ->> 'locationId', 'expiresOn', e ->> 'expiresOn', 'onHand', e ->> 'onHand')), '[]'::jsonb)
  into v_expiring
  from jsonb_array_elements("better_supabase"."expiring_lots"(inventory_overview.tenant,
    current_date + greatest(coalesce(inventory_overview.expiry_days, 30), 0))) e;

  return jsonb_build_object('levelCount', v_level_count, 'lowStockCount', v_low_count,
    'lowStock', v_low, 'expiring', v_expiring);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sessions_overview()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'count', jsonb_array_length(s.payload),
    'currentId', (select x ->> 'id' from jsonb_array_elements(s.payload) x where (x ->> 'current')::boolean limit 1),
    'sessions', s.payload)
  from (select better_supabase.list_my_sessions() as payload) s
$function$;

REVOKE ALL ON FUNCTION "api"."inventory_overview"(uuid, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."inventory_overview"(uuid, integer, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."sessions_overview"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."sessions_overview"() TO "authenticated";

REVOKE ALL ON FUNCTION "better_supabase"."inventory_overview"(uuid, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inventory_overview"(uuid, integer, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."sessions_overview"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."sessions_overview"() TO "authenticated";
