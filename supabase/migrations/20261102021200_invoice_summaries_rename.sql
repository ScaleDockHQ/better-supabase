SET local check_function_bodies = off;

DROP FUNCTION "api"."billing_invoices"(uuid);

CREATE OR REPLACE FUNCTION api.invoice_summaries (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', i.id,
    'kind', i.kind,
    'identifier', i.identifier,
    'title', i.title,
    'status', i.status,
    'currency', i.currency,
    'total', i.total::text,
    'balance', (i.total - i.credited_total - i.paid_total)::text,
    'issuedOn', i.issued_on,
    'dueOn', i.due_on,
    'overdue', i.status in ('issued', 'partially_paid') and i.due_on < current_date
  ) order by i.created_at desc), '[]'::jsonb)
  from better_supabase.invoices i
  where i.tenant_id = invoice_summaries.tenant;
$function$;

REVOKE ALL ON FUNCTION "api"."invoice_summaries"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."invoice_summaries"(uuid) TO "authenticated";
