-- better-supabase module: read-sets
-- @bsb-block read-sets@1 managed
-- @bsb-hash sha256:d44069252cb5f4f5c6f389661f4491647c0c9d8725d5ed713e769f3b0ad96ed4
-- One `stable` function per `defineReadSet` in `readSets`, so `db.$many(readSet, params)` is a single GET.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Functions for the read sets in `readSets` (better-supabase.config.ts); `gen` and `upgrade` rewrite them.
-- They are security invoker: RLS decides what each caller reads, as for any other query.

-- config.readSets
-- pipeline_overview
create or replace function public.rs_pipeline_overview(p jsonb)
  returns jsonb
  language sql stable security invoker set search_path = ''
as $rs$
  select jsonb_build_object(
    'customers', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from "public"."customers" as t0)),
    'board', to_jsonb("api"."deal_board"("pipeline" => ((p->>'pipelineId')::uuid)))
  )
$rs$;
revoke execute on function public.rs_pipeline_overview(jsonb) from public, anon, authenticated;
grant execute on function public.rs_pipeline_overview(jsonb) to authenticated;

-- workspace_summary
create or replace function public.rs_workspace_summary(p jsonb)
  returns jsonb
  language sql stable security invoker set search_path = ''
as $rs$
  select jsonb_build_object(
    'customers', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from "public"."customers" as t0)),
    'active', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from "public"."customers" as t0 where t0."status" = 'active')),
    'mine', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from "public"."customers" as t0 where t0."created_by" = (select auth.uid()))),
    'latestNote', jsonb_build_object('rows', (select coalesce(jsonb_agg(s.row), '[]'::jsonb) from (select json_build_object('body', t0."body", 'createdAt', t0."created_at") as row from "public"."notes" as t0 order by t0."created_at" desc limit 1) s), 'count', null)
  )
$rs$;
revoke execute on function public.rs_workspace_summary(jsonb) from public, anon, authenticated;
grant execute on function public.rs_workspace_summary(jsonb) to authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
