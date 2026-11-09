DROP POLICY "bsb_attachments_insert" ON "better_supabase"."attachments";

DROP POLICY "bsb_tenant_scope_insert" ON "better_supabase"."attachments";

CREATE POLICY "bsb_attachments_insert" ON "better_supabase"."attachments"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((uploaded_by = ( SELECT auth.uid() AS uid)) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('attachments.upload'::text) AS tenant_ids_with)) AND ((subject_type IS
    NULL) OR
CASE subject_type
    WHEN 'job'::text THEN (EXISTS ( SELECT 1
       FROM public.jobs s
      WHERE (((s.id)::text = attachments.subject_id) AND (s.organization_id = attachments.tenant_id))))
    ELSE better_supabase.attachment_subject_readable(subject_type, subject_id, tenant_id)
END) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."attachments"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH
    CHECK
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((uploaded_by = ( SELECT auth.uid() AS uid)) AND (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('attachments.upload'::text) AS tenant_ids_with)) AND ((subject_type IS NULL) OR
CASE subject_type
    WHEN 'job'::text THEN (EXISTS ( SELECT 1
       FROM public.jobs s
      WHERE (((s.id)::text = attachments.subject_id) AND (s.organization_id = attachments.tenant_id))))
    ELSE better_supabase.attachment_subject_readable(subject_type, subject_id, tenant_id)
END))));
