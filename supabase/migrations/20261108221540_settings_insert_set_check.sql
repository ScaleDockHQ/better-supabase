SET local check_function_bodies = off;

DROP POLICY "bsb_organization_settings_insert" ON "better_supabase"."organization_settings";

DROP POLICY "bsb_tenant_scope_insert" ON "better_supabase"."organization_settings";

CREATE OR REPLACE FUNCTION public.rs_pipeline_overview (
  p jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'customers', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from (select 1 from "public"."customers" as t0 limit 1001) as c)),
    'board', to_jsonb("api"."deal_board"("pipeline" => ((p->>'pipelineId')::uuid)))
  )
$function$;

CREATE OR REPLACE FUNCTION public.rs_workspace_summary (
  p jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'customers', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from (select 1 from "public"."customers" as t0 limit 1001) as c)),
    'active', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from (select 1 from "public"."customers" as t0 where t0."status" = 'active' limit 1001) as c)),
    'mine', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::bigint as count from (select 1 from "public"."customers" as t0 where t0."created_by" = (select auth.uid()) limit 1001) as c)),
    'latestNote', jsonb_build_object('rows', (select coalesce(jsonb_agg(s.row), '[]'::jsonb) from (select json_build_object('body', t0."body", 'createdAt', t0."created_at") as row from "public"."notes" as t0 order by t0."created_at" desc limit 1) s), 'count', null)
  )
$function$;

CREATE POLICY "bsb_organization_settings_insert" ON "better_supabase"."organization_settings"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('settings.update'::text) AS tenant_ids_with)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."organization_settings"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH
    CHECK
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('settings.update'::text) AS tenant_ids_with))));
