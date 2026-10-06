SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.customer_note_counts (
  p_customer_ids uuid[] DEFAULT NULL::uuid[]
)
  RETURNS TABLE (
    customer_id  uuid,
    note_count   bigint,
    last_note_at timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select c.id, count(n.id), max(n.created_at)
  from public.customers as c
  left join public.notes as n on n.customer_id = c.id
  where p_customer_ids is null or c.id = any (p_customer_ids)
  group by c.id;
$function$;

REVOKE ALL ON FUNCTION "public"."customer_note_counts"(uuid[]) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.customers_by_status (
  p_status text,
  p_limit  integer DEFAULT 50
)
  RETURNS SETOF public.customers
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select *
  from public.customers
  where status = p_status
  order by name
  limit p_limit;
$function$;

REVOKE ALL ON FUNCTION "public"."customers_by_status"(text, integer) FROM PUBLIC, "anon";

GRANT EXECUTE ON FUNCTION "public"."customer_note_counts"(uuid[]) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."customer_note_counts"(uuid[]) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."customer_note_counts"(uuid[]) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."customer_note_counts"(uuid[]) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."customers_by_status"(text, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."customers_by_status"(text, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."customers_by_status"(text, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."customers_by_status"(text, integer) TO "service_role";
