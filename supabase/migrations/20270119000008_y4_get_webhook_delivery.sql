SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.get_webhook_delivery (
  delivery uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_webhook_delivery"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_webhook_delivery (
  delivery uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_endpoint uuid;
  v_tenant uuid;
  v_enabled boolean;
begin
  select v."endpoint_id" into v_endpoint
  from "better_supabase"."webhook_deliveries" v where v."id" = get_webhook_delivery.delivery;
  if not found then
    return null;
  end if;
  select d."tenant_id", d."enabled" into v_tenant, v_enabled
  from "better_supabase"."webhook_endpoints" d where d."id" = v_endpoint;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhooks.read'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('id', v."id", 'endpointId', v."endpoint_id", 'type', v."event_type", 'status', v."status", 'attempt', v."attempt", 'responseStatus', v."response_status", 'durationMs', v."duration_ms", 'lastError', v."last_error", 'processedAt', v."processed_at", 'createdAt', v."created_at")
    from "better_supabase"."webhook_deliveries" v where v."id" = get_webhook_delivery.delivery
  );
end;
$function$;

REVOKE ALL ON FUNCTION "api"."get_webhook_delivery"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_webhook_delivery"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_webhook_delivery"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_webhook_delivery"(uuid) TO "authenticated", "service_role";
