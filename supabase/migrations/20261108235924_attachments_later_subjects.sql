DROP POLICY "bsb_attachments_insert" ON "better_supabase"."attachments";

DROP POLICY "bsb_attachments_read" ON "better_supabase"."attachments";

DROP POLICY "bsb_tenant_scope_insert" ON "better_supabase"."attachments";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."attachments";

CREATE POLICY "bsb_attachments_insert" ON "better_supabase"."attachments"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (((uploaded_by = ( SELECT auth.uid() AS uid)) AND (COALESCE(better_supabase.can('tenant'::text, tenant_id,
CASE subject_type
    WHEN 'message'::text THEN 'messages.send'::text
    WHEN 'conversation'::text THEN 'messages.send'::text
    WHEN 'expense_line'::text THEN 'expenses.submit'::text
    ELSE 'attachments.upload'::text
END), false) OR (((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('upload'::text) g(tenant, subject_type, subject_id)))) AND
     ((subject_type IS NULL) OR ((((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id))) OR
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id) AND ((s.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text) AS
        tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    ELSE better_supabase.attachment_subject_readable(subject_type, subject_id, tenant_id)
END)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_attachments_read" ON "better_supabase"."attachments"
  FOR SELECT
  TO "authenticated"
  USING
    ((((tenant_id IN ( SELECT better_supabase.tenant_ids_with('attachments.read'::text) AS tenant_ids_with)) OR (((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id)))) AND
     ((subject_type IS NULL) OR ((((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id))) OR
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id) AND ((s.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text) AS
        tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    ELSE better_supabase.attachment_subject_readable(subject_type, subject_id, tenant_id)
END))));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."attachments"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH
    CHECK
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((uploaded_by = ( SELECT auth.uid() AS uid)) AND
    (COALESCE(better_supabase.can('tenant'::text, tenant_id,
CASE subject_type
    WHEN 'message'::text THEN 'messages.send'::text
    WHEN 'conversation'::text THEN 'messages.send'::text
    WHEN 'expense_line'::text THEN 'expenses.submit'::text
    ELSE 'attachments.upload'::text
END), false) OR (((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('upload'::text) g(tenant, subject_type, subject_id)))) AND
     ((subject_type IS NULL) OR ((((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id))) OR
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id) AND ((s.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text) AS
        tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    ELSE better_supabase.attachment_subject_readable(subject_type, subject_id, tenant_id)
END)))));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."attachments"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('attachments.read'::text) AS tenant_ids_with)) OR (((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id)))) AND
     ((subject_type IS NULL) OR ((((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id))) OR
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id) AND ((s.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text) AS
        tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    ELSE better_supabase.attachment_subject_readable(subject_type, subject_id, tenant_id)
END)))));
