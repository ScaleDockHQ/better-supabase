-- Read set functions for apps/examples/nextjs (better-supabase gen writes them to supabase/schemas).
create or replace function public.rs_workspace_summary(p jsonb)
  returns jsonb
  language sql stable security invoker set search_path = ''
as $rs$
  select jsonb_build_object(
    'customers', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::int as count from "public"."customers" as t0)),
    'active', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::int as count from "public"."customers" as t0 where t0."status" = 'active')),
    'mine', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::int as count from "public"."customers" as t0 where t0."created_by" = ((p->>'userId')::uuid))),
    'latestNote', jsonb_build_object('rows', (select coalesce(jsonb_agg(s.row), '[]'::jsonb) from (select json_build_object('body', t0."body", 'createdAt', t0."created_at") as row from "public"."notes" as t0 order by t0."created_at" desc limit 1) s), 'count', null)
  )
$rs$;

-- The vector-search SQL kit module for apps/examples/nextjs
-- (better-supabase sql add vector-search, with `vectorSearch: { notes: 'embedding' }`).
create or replace function "public"."search_notes"(query extensions.vector, k integer default 10)
returns setof "public"."notes"
language sql
stable
security invoker
set search_path = ''
set hnsw.iterative_scan = 'strict_order'
as $$
  select t.* from "public"."notes" t
  where t."embedding" is not null
  order by t."embedding" operator(extensions.<=>) query
  limit least(greatest(k, 1), 1000)
$$;
