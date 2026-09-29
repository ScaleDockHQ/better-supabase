-- better-supabase SQL kit: read-sets (0.0.0)
-- One `stable` function per `defineReadSet` in `readSets`, so `db.$many(readSet, params)` is a single GET.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.

-- Functions for the read sets in `readSets` (better-supabase.config.ts); `gen` and `sql sync` rewrite them.
-- They are security invoker: RLS decides what each caller reads, as for any other query.

-- config.readSets
-- workspace_summary
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
revoke execute on function public.rs_workspace_summary(jsonb) from public, anon, authenticated;
grant execute on function public.rs_workspace_summary(jsonb) to authenticated;
