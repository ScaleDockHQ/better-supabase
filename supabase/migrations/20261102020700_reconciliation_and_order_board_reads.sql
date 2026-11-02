SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.bank_reconciliation_board (
  account_id uuid,
  line_limit integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."bank_reconciliation_board"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.order_status_board (
  tenant     uuid,
  per_status integer DEFAULT 20
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."order_status_board"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.bank_reconciliation_board (
  account_id uuid,
  line_limit integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with src as (
    select "better_supabase"."list_bank_transactions"(bank_reconciliation_board.account_id,
      jsonb_build_object('limit', bank_reconciliation_board.line_limit)) as payload
  )
  select jsonb_build_object(
    'status', "better_supabase"."bank_reconciliation_status"(bank_reconciliation_board.account_id, null),
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', x.line -> 'id', 'bookedOn', x.line -> 'bookedOn', 'amount', x.line -> 'amount',
          'currency', x.line -> 'currency', 'counterpartyName', x.line -> 'counterpartyName',
          'counterpartyIban', x.line -> 'counterpartyIban', 'remittance', x.line -> 'remittance',
          'status', x.line -> 'status') order by x.position)
      from jsonb_array_elements(src.payload) with ordinality as x(line, position)
    ), '[]'::jsonb),
    'suggestions', coalesce((
      select jsonb_agg(best.s || jsonb_build_object('transactionId', x.line ->> 'id') order by x.position)
      from jsonb_array_elements(src.payload) with ordinality as x(line, position)
      cross join lateral (
        select s from jsonb_array_elements("better_supabase"."suggest_bank_matches"((x.line ->> 'id')::uuid)) s
        where x.line ->> 'status' = 'unmatched' and s ->> 'targetType' = 'invoice' limit 1) best
    ), '[]'::jsonb))
  from src;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.order_status_board (
  tenant     uuid,
  per_status integer DEFAULT 20
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('columns', coalesce(jsonb_agg(col order by rank, col ->> 'status'), '[]'::jsonb))
  from (
    select
      array_position(array['pending_payment', 'confirmed', 'paid', 'fulfilled', 'completed', 'cancelled', 'refunded'], g.raw::text) as rank,
      jsonb_build_object(
        'status', g.label,
        'count', g.n,
        'totals', g.totals,
        'orders', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', x."id", 'number', x."number", 'customerId', x."customer_id",
            'currency', x."currency", 'total', x."total"::text,
            'paidTotal', x."paid_total"::text, 'placedAt', x."placed_at") order by x."placed_at" desc, x."id")
          from (
            select * from "better_supabase"."orders" y
            where y."tenant_id" = order_status_board.tenant and y."status" = g.raw
            order by y."placed_at" desc, y."id"
            limit greatest(coalesce(order_status_board.per_status, 20), 0)
          ) x), '[]'::jsonb)
      ) as col
    from (
      select s.raw, s.label, sum(s.n)::integer as n,
        jsonb_agg(jsonb_build_object('currency', s.currency, 'total', s.total::text, 'paid', s.paid::text) order by s.currency) as totals
      from (
        select z."status" as raw, z."status" as label,
          z."currency" as currency, count(*) as n,
          sum(z."total") as total, sum(z."paid_total") as paid
        from "better_supabase"."orders" z
        where z."tenant_id" = order_status_board.tenant
        group by z."status", z."currency"
      ) s
      group by s.raw, s.label
    ) g
  ) cols
$function$;

REVOKE ALL ON FUNCTION "api"."bank_reconciliation_board"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."bank_reconciliation_board"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."order_status_board"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."order_status_board"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."bank_reconciliation_board"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."bank_reconciliation_board"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."order_status_board"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."order_status_board"(uuid, integer) TO "authenticated", "service_role";
