SET local check_function_bodies = off;

DROP FUNCTION "api"."complete_push_receipts"(jsonb);

DROP FUNCTION "better_supabase"."complete_push_receipts"(jsonb);

CREATE OR REPLACE FUNCTION api.complete_push_receipts (
  receipts jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."complete_push_receipts"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_push_receipts (
  receipts jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
  v_events jsonb := '[]'::jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads push tickets' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  if jsonb_typeof(complete_push_receipts.receipts) <> 'array' or jsonb_array_length(complete_push_receipts.receipts) > 1000 then
    raise exception 'pass at most 1000 receipts' using errcode = '22023', hint = 'PUSH_TOO_MANY';
  end if;
  -- The delivery's provider message id is Expo's first ticket id, so every
  -- receipt of the delivery records its event on that message, once per
  -- ticket. The events stored now come back for the client to emit.
  select coalesce(jsonb_agg(e.recorded || jsonb_build_object('provider_event_id', e.event_id)), '[]'::jsonb)
  into v_events
  from (
    select "better_supabase"."record_delivery_event"(
      'expo',
      d."provider_message_id",
      case when r ->> 'status' = 'ok' then 'delivered' else 'bounced' end,
      'expo-receipt:' || (r ->> 'id'),
      now(),
      jsonb_strip_nulls(jsonb_build_object('token', x."token", 'error', r ->> 'error', 'message', r ->> 'message')),
      false
    ) as recorded, 'expo-receipt:' || (r ->> 'id') as event_id
    from "better_supabase"."push_tickets" x
    join "better_supabase"."notification_deliveries" d on d."id" = x."delivery_id"
    cross join jsonb_array_elements(complete_push_receipts.receipts) r
    where x."ticket_id" = r ->> 'id'
      and x."checked_at" is null
      and d."provider_message_id" is not null
  ) e
  where coalesce((e.recorded ->> 'recorded')::boolean, false);
  update "better_supabase"."push_tickets" x set
    "status" = case when r ->> 'status' = 'ok' then 'ok' else 'error' end,
    "error" = case when r ->> 'status' = 'ok' then null else coalesce(r ->> 'error', 'Unknown') end,
    "checked_at" = now()
  from jsonb_array_elements(complete_push_receipts.receipts) r
  where x."ticket_id" = r ->> 'id'
    and x."checked_at" is null;
  get diagnostics v_count = row_count;
  return jsonb_build_object('updated', v_count, 'events', v_events);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."complete_push_receipts"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."complete_push_receipts"(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."complete_push_receipts"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."complete_push_receipts"(jsonb) TO "service_role";
