SET local check_function_bodies = off;

DROP POLICY "bsb_attachments_insert" ON "better_supabase"."attachments";

DROP POLICY "bsb_attachments_read" ON "better_supabase"."attachments";

DROP POLICY "bsb_tenant_scope_insert" ON "better_supabase"."attachments";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."attachments";

CREATE OR REPLACE FUNCTION better_supabase.importing()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select better_supabase.import_run() is not null;
$function$;

CREATE POLICY "bsb_attachments_insert" ON "better_supabase"."attachments"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((uploaded_by = ( SELECT auth.uid() AS uid)) AND COALESCE(better_supabase.can('tenant'::text, tenant_id, 'attachments.upload'::text), false) AND ((subject_type IS NULL) OR
CASE subject_type
    WHEN 'job'::text THEN (EXISTS ( SELECT 1
       FROM public.jobs s
      WHERE (((s.id)::text = attachments.subject_id) AND (s.organization_id = attachments.tenant_id))))
    ELSE false
END) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_attachments_read" ON "better_supabase"."attachments"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('attachments.read'::text) AS tenant_ids_with)) AND ((subject_type IS NULL) OR
CASE subject_type
    WHEN 'job'::text THEN (EXISTS ( SELECT 1
       FROM public.jobs s
      WHERE (((s.id)::text = attachments.subject_id) AND (s.organization_id = attachments.tenant_id))))
    ELSE false
END)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."attachments"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH
    CHECK
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((uploaded_by = ( SELECT auth.uid() AS uid)) AND
    COALESCE(better_supabase.can('tenant'::text, tenant_id, 'attachments.upload'::text), false) AND ((subject_type IS NULL) OR
CASE subject_type
    WHEN 'job'::text THEN (EXISTS ( SELECT 1
       FROM public.jobs s
      WHERE (((s.id)::text = attachments.subject_id) AND (s.organization_id = attachments.tenant_id))))
    ELSE false
END))));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."attachments"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('attachments.read'::text) AS tenant_ids_with)) AND ((subject_type IS NULL) OR
CASE subject_type
    WHEN 'job'::text THEN (EXISTS ( SELECT 1
       FROM public.jobs s
      WHERE (((s.id)::text = attachments.subject_id) AND (s.organization_id = attachments.tenant_id))))
    ELSE false
END))));

REVOKE ALL ON FUNCTION "better_supabase"."importing"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."importing"() TO "anon", "authenticated", "service_role";
