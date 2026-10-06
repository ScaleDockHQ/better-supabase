SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.search_notes_scores (
  query extensions.vector,
  k     integer           DEFAULT 10
)
  RETURNS TABLE (
    id    jsonb,
    score double precision
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  SET "hnsw.iterative_scan" TO 'strict_order'
  AS $function$
  select to_jsonb(r.id), r.score from (
  with vector_hits as materialized (
    select t."id" as id, t."embedding" operator(extensions.<=>) query as distance
    from "public"."notes" t
    where t."embedding" is not null
    order by t."embedding" operator(extensions.<=>) query
    limit least(greatest(k, 1), 1000)
  ),
  vector_ranked as (
    select h.id, h.distance, row_number() over (order by h.distance) as rank from vector_hits h
  ),
  fused as (
    select v.id, 1 - v.distance as score from vector_ranked v
  )
  select f.id, f.score::double precision as score from fused f
  order by score desc
  limit least(greatest(k, 1), 1000)
  ) r
  order by r.score desc
$function$;

REVOKE ALL ON FUNCTION "public"."search_notes_scores"(extensions.vector, integer) FROM PUBLIC, "anon";

GRANT EXECUTE ON FUNCTION "public"."search_notes_scores"(extensions.vector, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."search_notes_scores"(extensions.vector, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."search_notes_scores"(extensions.vector, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."search_notes_scores"(extensions.vector, integer) TO "service_role";
